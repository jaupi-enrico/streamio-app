import 'dart:async';

import 'package:dio/dio.dart';

import '../../shared/user_facing_error.dart';
import 'token_store.dart';

/// Raised when a request needs a session and there isn't a usable one left
/// (no refresh token, or the refresh itself was rejected). The router listens
/// for this via [ApiClient.onAuthLost] and sends the user to /login.
class SessionExpiredException implements Exception {
  const SessionExpiredException([this.message = 'Session expired']);
  final String message;
  @override
  String toString() => message;
}

/// What came of an attempt to renew the access token.
///
/// The distinction that matters is [transient] vs [dead]: only the latter is
/// the server saying the refresh token is no good. A 429, a 5xx, a proxy that
/// swallowed the call, or no connection at all say nothing about the session,
/// and treating them as a sign-out is how a working login gets thrown away.
enum _RefreshOutcome {
  /// A new access token is in the store; replay the request.
  refreshed,

  /// The refresh didn't happen, but the session is still presumed good.
  transient,

  /// The server rejected the refresh token, or there was none. Signed out.
  dead,
}

/// A failed API call, carrying the server's own `{ error: "..." }` message so
/// screens can surface it instead of a generic "something went wrong".
class ApiException implements Exception, UserFacingError {
  const ApiException(this.message, {this.statusCode});

  @override
  final String message;
  final int? statusCode;

  bool get isNotFound => statusCode == 404;
  bool get isForbidden => statusCode == 403;

  @override
  String toString() => message;
}

/// The single HTTP entry point to the backend.
///
/// Mirrors the contract of `apiFetch()` in `public/scripts/auth.js`: attach
/// the bearer token, and on a 401 try exactly one silent refresh and replay
/// the request; a second 401 tears the session down. Concurrent 401s share
/// one in-flight refresh rather than each rotating the (single-use, rotating)
/// refresh token and invalidating one another.
class ApiClient {
  ApiClient({required String baseUrl, TokenStore? tokens, Dio? dio})
      : _baseUrl = baseUrl,
        tokens = tokens ?? TokenStore(),
        _dio = dio ?? Dio() {
    _dio.options = _dio.options.copyWith(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        ..._dio.options.headers,
        // Opts this client into the native-token flow on the backend.
        'X-Client': 'app',
      },
      // Non-2xx is handled explicitly below so the server's error body is
      // still available to read.
      validateStatus: (status) => status != null && status < 500,
      // Redirects are followed by hand in [_followRedirects] — never by
      // dart:io. Its auto-follow drops the Authorization header on the way to
      // the new host, so an authenticated GET arrives anonymous and 401s. A
      // Streamio install commonly sits behind a DDNS name that redirects to
      // an ephemeral tunnel URL, which makes every such request cross-host.
      followRedirects: false,
    );
  }

  static const _maxRedirects = 5;

  final String _baseUrl;
  final Dio _dio;
  final TokenStore tokens;

  Future<_RefreshOutcome>? _refreshInFlight;
  final _authLost = StreamController<void>.broadcast();

  String get baseUrl => _baseUrl;

  /// Emits when the session is gone and the user has to log in again.
  Stream<void> get onAuthLost => _authLost.stream;

  /// Renews the access token outside the request path, for the one caller
  /// that can't go through it: the watch-party WebSocket, which carries the
  /// access token in its handshake URL and so cannot retry a 401 the way a
  /// request does. Returns true when a new token is in the store.
  ///
  /// Shares the in-flight refresh with the request path, and never emits
  /// [onAuthLost] — a socket that can't authenticate is a reason to stop
  /// reconnecting, not to throw the user out of the app.
  Future<bool> renewAccessToken() async =>
      await _refreshOnce() == _RefreshOutcome.refreshed;

  void dispose() {
    _authLost.close();
    _dio.close(force: true);
  }

  /// Absolute URL for a path on this server — needed wherever a URL is handed
  /// to something that isn't this client (the media player, the Cast sender,
  /// the WebSocket room connection).
  String absolute(String path) =>
      path.startsWith('http') ? path : '$_baseUrl$path';

  /// `wss://host/ws/rooms/...` for this origin.
  String webSocketUrl(String path) {
    final uri = Uri.parse(absolute(path));
    return uri.replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws').toString();
  }

  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? query,
    bool authenticated = false,
  }) =>
      _send<T>('GET', path, query: query, authenticated: authenticated);

  Future<T> post<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool authenticated = false,
  }) =>
      _send<T>('POST', path,
          body: body, query: query, authenticated: authenticated);

  Future<T> put<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool authenticated = false,
  }) =>
      _send<T>('PUT', path,
          body: body, query: query, authenticated: authenticated);

  Future<T> patch<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool authenticated = false,
  }) =>
      _send<T>('PATCH', path,
          body: body, query: query, authenticated: authenticated);

  Future<T> delete<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool authenticated = false,
  }) =>
      _send<T>('DELETE', path,
          body: body, query: query, authenticated: authenticated);

  Future<T> _send<T>(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool authenticated = false,
  }) async {
    var response = await _followRedirects(
      await _raw(method, path,
          body: body, query: query, authenticated: authenticated),
      method: method,
      body: body,
      authenticated: authenticated,
    );

    if (response.statusCode == 401 && authenticated) {
      final outcome = await _refreshOnce();
      if (outcome == _RefreshOutcome.dead) {
        _authLost.add(null);
        throw const SessionExpiredException();
      }
      if (outcome == _RefreshOutcome.transient) {
        // The session is still good; renewing it just didn't get through.
        // Fail this one call and let the caller retry.
        throw const ApiException(
          'Could not renew the session. Check your connection and try again.',
        );
      }
      response = await _followRedirects(
        await _raw(method, path, body: body, query: query, authenticated: true),
        method: method,
        body: body,
        authenticated: true,
      );

      if (response.statusCode == 401) {
        await tokens.clear();
        _authLost.add(null);
        throw const SessionExpiredException();
      }
    }

    return _unwrap<T>(response);
  }

  /// Replays a request against a `Location` when the server redirects.
  ///
  /// dart:io only auto-follows redirects for GET and HEAD, so every write the
  /// app makes — sign-in, resolving a stream, saving progress, watchlist,
  /// ratings, shares, rooms — surfaces the 3xx raw and would otherwise fail
  /// with "Request failed (HTTP 302)". That's not hypothetical here: the
  /// `redirect/` tunnel in front of a Streamio install exists to redirect, and
  /// reverse proxies routinely bounce a request to a canonical host or path.
  ///
  /// The method and body are preserved across the hop, including for 301/302
  /// where a browser would downgrade to GET. A browser does that for the sake
  /// of history and forms; replaying a `POST /api/auth/login` as a bodyless
  /// GET would just fail. What's wanted here is the same call, at the address
  /// the server named.
  Future<Response<dynamic>> _followRedirects(
    Response<dynamic> response, {
    required String method,
    Object? body,
    required bool authenticated,
  }) async {
    var current = response;

    for (var hop = 0; hop < _maxRedirects; hop++) {
      final status = current.statusCode ?? 0;
      if (status < 300 || status > 399) return current;

      final location = current.headers.value('location');
      if (location == null || location.isEmpty) return current;

      final from = current.realUri;
      final target = from.resolve(location);

      // Don't carry the bearer token onto a plaintext hop; a redirect that
      // downgrades https→http is either a misconfiguration or an attack, and
      // neither deserves the token.
      final downgraded = from.scheme == 'https' && target.scheme == 'http';

      final headers = <String, String>{};
      if (authenticated && !downgraded) {
        final token = await tokens.accessToken;
        if (token != null) headers['Authorization'] = 'Bearer $token';
      }

      try {
        current = await _dio.request<dynamic>(
          target.toString(),
          data: body,
          options: Options(method: method, headers: headers),
        );
      } on DioException catch (err) {
        if (err.response != null) return err.response!;
        throw ApiException(_networkMessage(err));
      }
    }

    return current;
  }

  Future<Response<dynamic>> _raw(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool authenticated = false,
  }) async {
    final headers = <String, String>{};
    if (authenticated) {
      final token = await tokens.accessToken;
      if (token == null) {
        // No access token yet (fresh launch with a stored refresh token):
        // get one before the first call rather than burning a 401.
        final outcome = await _refreshOnce();
        if (outcome == _RefreshOutcome.dead) {
          _authLost.add(null);
          throw const SessionExpiredException('Not authenticated');
        }
        if (outcome == _RefreshOutcome.transient) {
          throw const ApiException(
            'Could not reach the server to renew the session.',
          );
        }
      }
      final current = await tokens.accessToken;
      if (current != null) headers['Authorization'] = 'Bearer $current';
    }

    try {
      return await _dio.request<dynamic>(
        path,
        data: body,
        queryParameters: query,
        options: Options(method: method, headers: headers),
      );
    } on DioException catch (err) {
      if (err.response != null) return err.response!;
      throw ApiException(_networkMessage(err));
    }
  }

  /// One refresh at a time. The backend rotates refresh tokens on use
  /// (`rotateRefreshToken`), so two parallel refreshes would race and one
  /// would revoke the other's brand-new token.
  /// Reports whether a *new* access token was actually obtained — not merely
  /// whether one happens to be lying around. Reporting success without having
  /// refreshed would send the caller off to replay a request with the very
  /// token that just 401'd.
  Future<_RefreshOutcome> _refreshOnce() {
    final pending = _refreshInFlight;
    if (pending != null) return pending;

    final future = _doRefresh()
        // Anything unforeseen in here is a failed refresh, never a verdict on
        // the session; _doRefresh only clears tokens when the server says to.
        .catchError((Object _) => _RefreshOutcome.transient)
        .whenComplete(() => _refreshInFlight = null);

    _refreshInFlight = future;
    return future;
  }

  Future<_RefreshOutcome> _doRefresh() async {
    final refreshToken = await tokens.refreshToken;
    if (refreshToken == null) {
      // Nothing to refresh with, and the caller only asks after a 401 (or
      // with no access token at all), so there is no session left to save.
      return _RefreshOutcome.dead;
    }

    final body = {'refresh_token': refreshToken};

    final Response<dynamic> response;
    try {
      // Redirects are followed by hand here for the same reason as every
      // other call: this client has auto-follow off, and an install behind
      // the `redirect/` tunnel answers with a 3xx. Left unfollowed it looks
      // like a non-200 — which used to be read as "the server rejected the
      // token" and signed the user out on the spot.
      response = await _followRedirects(
        await _dio.post<dynamic>('/api/auth/refresh', data: body),
        method: 'POST',
        body: body,
        authenticated: false,
      );
    } on DioException {
      // Unreachable server, timeout, TLS failure: says nothing about the
      // session, so the stored tokens stay put for the next attempt.
      return _RefreshOutcome.transient;
    } on ApiException {
      return _RefreshOutcome.transient;
    }

    final status = response.statusCode ?? 0;
    final data = response.data;

    if (status == 200 && data is Map) {
      final access = data['access_token']?.toString();
      if (access == null) return _RefreshOutcome.transient;
      await tokens.save(
        accessToken: access,
        refreshToken: data['refresh_token']?.toString(),
      );
      return _RefreshOutcome.refreshed;
    }

    // Only the auth endpoint's own verdict ends a session. Everything else a
    // server or a proxy in between can answer with — 429 from the refresh
    // rate limiter, 502/504 from a tunnel that dropped, a 3xx that led
    // nowhere, an HTML error page — is a failed attempt, not a sign-out.
    if (status == 401 || status == 403) {
      await tokens.clear();
      return _RefreshOutcome.dead;
    }

    return _RefreshOutcome.transient;
  }

  T _unwrap<T>(Response<dynamic> response) {
    final status = response.statusCode ?? 0;
    final data = response.data;

    if (status >= 200 && status < 300) {
      if (T == Null || data == null) return null as T;
      return data as T;
    }

    throw ApiException(_errorMessage(data, status, response), statusCode: status);
  }

  String _errorMessage(dynamic data, int status, Response<dynamic> response) {
    if (data is Map) {
      final message = data['error'] ?? data['message'];
      if (message != null) return message.toString();
    }

    // A 3xx here means the redirect couldn't be followed (no Location, or too
    // many hops). Naming the target makes a proxy loop diagnosable instead of
    // just "HTTP 302".
    if (status >= 300 && status <= 399) {
      final location = response.headers.value('location');
      return location == null
          ? 'The server redirected without saying where (HTTP $status). '
              'Check the reverse proxy in front of it.'
          : 'The server kept redirecting to $location. '
              'Check the reverse proxy in front of it.';
    }

    return 'Request failed (HTTP $status)';
  }

  String _networkMessage(DioException err) => switch (err.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          'The server took too long to respond.',
        DioExceptionType.badCertificate =>
          'The server\'s TLS certificate was rejected.',
        DioExceptionType.connectionError =>
          'Could not reach the server. Check the address and your connection.',
        _ => err.message ?? 'Network error',
      };
}
