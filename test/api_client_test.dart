import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamio/core/api/api_client.dart';
import 'package:streamio/core/api/token_store.dart';

/// An in-memory stand-in for the platform keystore, so the token handling can
/// be exercised without a device.
class _MemoryStorage extends FlutterSecureStorage {
  _MemoryStorage([Map<String, String>? initial])
      : _values = {...?initial},
        super();

  final Map<String, String> _values;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _values.remove(key);
}

/// Scripted HTTP: each request is answered by [handler], and every request is
/// recorded so the test can assert on what actually went over the wire.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body, int statusCode) => ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

/// What the `redirect/` tunnel serves — a plain 200 of HTML — while the host
/// behind it is still coming up.
const _waitingPage =
    '<!DOCTYPE html><html lang="it"><head><title>Streamio</title></head>'
    '<body>Starting up…</body></html>';

ResponseBody _html(String body, {int statusCode = 200}) =>
    ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['text/html; charset=utf-8'],
      },
    );

ResponseBody _redirect(String location, {int statusCode = 302}) =>
    ResponseBody.fromString(
      '',
      statusCode,
      headers: {
        'location': [location],
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ApiClient buildClient({
    required _ScriptedAdapter adapter,
    Map<String, String>? tokens,
    String baseUrl = 'https://streamio.example',
  }) {
    final dio = Dio()..httpClientAdapter = adapter;
    return ApiClient(
      baseUrl: baseUrl,
      tokens: TokenStore(storage: _MemoryStorage(tokens)),
      dio: dio,
    );
  }

  group('authenticated requests', () {
    test('attach the bearer token and the app client header', () async {
      final adapter = _ScriptedAdapter((_) => _json('{"ok":true}', 200));
      final client = buildClient(
        adapter: adapter,
        tokens: {
          'streamio.access_token': 'access-1',
          'streamio.refresh_token': 'refresh-1',
        },
      );

      await client.get<Map<String, dynamic>>('/api/account/me', authenticated: true);

      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.headers['Authorization'], 'Bearer access-1');
      // Opts into the backend's native-token behavior.
      expect(adapter.requests.single.headers['X-Client'], 'app');
    });

    test('do not send a token when the call is unauthenticated', () async {
      final adapter = _ScriptedAdapter((_) => _json('{"data":[]}', 200));
      final client = buildClient(
        adapter: adapter,
        tokens: {'streamio.access_token': 'access-1'},
      );

      await client.get<Map<String, dynamic>>('/api/home');

      expect(adapter.requests.single.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('401 handling', () {
    test('refreshes once and replays the request', () async {
      var meCalls = 0;
      final adapter = _ScriptedAdapter((options) {
        if (options.path == '/api/auth/refresh') {
          return _json(
              '{"access_token":"access-2","refresh_token":"refresh-2"}', 200);
        }
        meCalls++;
        // First attempt is rejected; the replay carries the new token.
        return options.headers['Authorization'] == 'Bearer access-2'
            ? _json('{"id":"u1","email":"a@b.c"}', 200)
            : _json('{"error":"expired"}', 401);
      });

      final client = buildClient(
        adapter: adapter,
        tokens: {
          'streamio.access_token': 'access-1',
          'streamio.refresh_token': 'refresh-1',
        },
      );

      final result = await client
          .get<Map<String, dynamic>>('/api/account/me', authenticated: true);

      expect(result['id'], 'u1');
      expect(meCalls, 2);
      expect(await client.tokens.accessToken, 'access-2');
      // The backend rotates refresh tokens, so the new one must be stored.
      expect(await client.tokens.refreshToken, 'refresh-2');
    });

    test('sends the refresh token in the body, since there is no cookie jar',
        () async {
      final adapter = _ScriptedAdapter((options) {
        if (options.path == '/api/auth/refresh') {
          return _json('{"access_token":"access-2"}', 200);
        }
        return options.headers['Authorization'] == 'Bearer access-2'
            ? _json('{"ok":true}', 200)
            : _json('{"error":"expired"}', 401);
      });

      final client = buildClient(
        adapter: adapter,
        tokens: {
          'streamio.access_token': 'access-1',
          'streamio.refresh_token': 'refresh-1',
        },
      );

      await client.get<Map<String, dynamic>>('/api/account/me', authenticated: true);

      final refreshCall = adapter.requests
          .firstWhere((request) => request.path == '/api/auth/refresh');
      expect((refreshCall.data as Map)['refresh_token'], 'refresh-1');
    });

    test('gives up and clears the session when the refresh is rejected',
        () async {
      final adapter = _ScriptedAdapter((options) {
        if (options.path == '/api/auth/refresh') {
          return _json('{"error":"invalid"}', 401);
        }
        return _json('{"error":"expired"}', 401);
      });

      final client = buildClient(
        adapter: adapter,
        tokens: {
          'streamio.access_token': 'access-1',
          'streamio.refresh_token': 'refresh-1',
        },
      );

      final authLost = client.onAuthLost.first;

      await expectLater(
        client.get<Map<String, dynamic>>('/api/account/me', authenticated: true),
        throwsA(isA<SessionExpiredException>()),
      );
      await authLost.timeout(const Duration(seconds: 1));
      expect(await client.tokens.refreshToken, isNull);
    });

    test('concurrent 401s share a single refresh', () async {
      var refreshCalls = 0;
      final adapter = _ScriptedAdapter((options) {
        if (options.path == '/api/auth/refresh') {
          refreshCalls++;
          return _json(
              '{"access_token":"access-2","refresh_token":"refresh-2"}', 200);
        }
        return options.headers['Authorization'] == 'Bearer access-2'
            ? _json('{"ok":true}', 200)
            : _json('{"error":"expired"}', 401);
      });

      final client = buildClient(
        adapter: adapter,
        tokens: {
          'streamio.access_token': 'access-1',
          'streamio.refresh_token': 'refresh-1',
        },
      );

      await Future.wait([
        client.get<Map<String, dynamic>>('/api/account/watchlist', authenticated: true),
        client.get<Map<String, dynamic>>('/api/account/favorites', authenticated: true),
        client.get<Map<String, dynamic>>('/api/account/ratings', authenticated: true),
      ]);

      // Refresh tokens are single-use and rotate, so a second concurrent
      // refresh would revoke the first one's brand-new token.
      expect(refreshCalls, 1);
    });
  });

  // Only the auth endpoint saying "no" ends a session. Anything else that can
  // stop a refresh from landing — the refresh rate limiter, a tunnel that
  // dropped, an unfollowed redirect, no network — leaves a perfectly good
  // login in place, and treating it as a sign-out is what used to bounce
  // people back to the login screen at random.
  group('a refresh that fails without being rejected', () {
    /// Runs one authenticated call whose 401 triggers a refresh answered by
    /// [refreshResponse], and reports what became of the session.
    Future<({bool authLost, String? access, String? refresh, Object? error})>
        runRefreshFailure(ResponseBody refreshResponse) async {
      final adapter = _ScriptedAdapter((options) =>
          options.path == '/api/auth/refresh'
              ? refreshResponse
              : _json('{"error":"expired"}', 401));

      final client = buildClient(
        adapter: adapter,
        tokens: {
          'streamio.access_token': 'access-1',
          'streamio.refresh_token': 'refresh-1',
        },
      );

      var authLost = false;
      final subscription = client.onAuthLost.listen((_) => authLost = true);

      Object? error;
      try {
        await client.get<Map<String, dynamic>>('/api/account/me',
            authenticated: true);
      } catch (err) {
        error = err;
      }

      // Let the onAuthLost broadcast, if any, reach the listener.
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      return (
        authLost: authLost,
        access: await client.tokens.accessToken,
        refresh: await client.tokens.refreshToken,
        error: error,
      );
    }

    test('a 429 from the refresh rate limiter keeps the session', () async {
      final result =
          await runRefreshFailure(_json('{"error":"Too Many Requests"}', 429));

      expect(result.authLost, isFalse);
      expect(result.access, 'access-1');
      expect(result.refresh, 'refresh-1');
      expect(result.error, isA<ApiException>());
      expect(result.error, isNot(isA<SessionExpiredException>()));
    });

    test('a 502 from a proxy in front of the server keeps the session',
        () async {
      final result = await runRefreshFailure(_json('{"error":"bad gateway"}', 502));

      expect(result.authLost, isFalse);
      expect(result.refresh, 'refresh-1');
    });

    test('an unreachable server keeps the session', () async {
      final adapter = _ScriptedAdapter((_) => throw DioException.connectionError(
            requestOptions: RequestOptions(path: '/'),
            reason: 'offline',
          ));

      final client = buildClient(
        adapter: adapter,
        tokens: {
          'streamio.access_token': 'access-1',
          'streamio.refresh_token': 'refresh-1',
        },
      );

      var authLost = false;
      final subscription = client.onAuthLost.listen((_) => authLost = true);

      await expectLater(
        client.get<Map<String, dynamic>>('/api/account/me', authenticated: true),
        throwsA(isA<ApiException>()),
      );

      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(authLost, isFalse);
      expect(await client.tokens.refreshToken, 'refresh-1');
    });

    // The install commonly sits behind the `redirect/` tunnel, so the refresh
    // has to follow a 3xx by hand like every other call — this client has
    // dart:io's auto-follow turned off.
    test('a redirected refresh is followed and still renews the session',
        () async {
      final adapter = _ScriptedAdapter((options) {
        if (options.path == '/api/auth/refresh') {
          return _redirect('https://tunnel.example/api/auth/refresh');
        }
        if (options.uri.toString() ==
            'https://tunnel.example/api/auth/refresh') {
          return _json(
              '{"access_token":"access-2","refresh_token":"refresh-2"}', 200);
        }
        return options.headers['Authorization'] == 'Bearer access-2'
            ? _json('{"id":"u1"}', 200)
            : _json('{"error":"expired"}', 401);
      });

      final client = buildClient(
        adapter: adapter,
        tokens: {
          'streamio.access_token': 'access-1',
          'streamio.refresh_token': 'refresh-1',
        },
      );

      var authLost = false;
      final subscription = client.onAuthLost.listen((_) => authLost = true);

      final result = await client
          .get<Map<String, dynamic>>('/api/account/me', authenticated: true);

      await subscription.cancel();

      expect(result['id'], 'u1');
      expect(authLost, isFalse);
      expect(await client.tokens.accessToken, 'access-2');
      expect(await client.tokens.refreshToken, 'refresh-2');
    });
  });

  // A server that only sets the refresh token as an httpOnly cookie (the web
  // flow) leaves a native client holding an access token and nothing else.
  // That is a degraded session, not a dead one, and must not be thrown away.
  group('access token without a refresh token', () {
    test('is still reported as a session', () async {
      final client = buildClient(
        adapter: _ScriptedAdapter((_) => _json('{}', 200)),
        tokens: {'streamio.access_token': 'access-1'},
      );

      expect(await client.tokens.hasSession, isTrue);
    });

    test('is used for authenticated requests', () async {
      final adapter = _ScriptedAdapter((_) => _json('{"id":"u1"}', 200));
      final client = buildClient(
        adapter: adapter,
        tokens: {'streamio.access_token': 'access-1'},
      );

      await client.get<Map<String, dynamic>>('/api/account/me',
          authenticated: true);

      expect(adapter.requests.single.headers['Authorization'], 'Bearer access-1');
    });

    test('a 401 does not wipe the access token on the way out', () async {
      final adapter = _ScriptedAdapter((_) => _json('{"error":"expired"}', 401));
      final client = buildClient(
        adapter: adapter,
        tokens: {'streamio.access_token': 'access-1'},
      );

      await expectLater(
        client.get<Map<String, dynamic>>('/api/account/me', authenticated: true),
        throwsA(isA<SessionExpiredException>()),
      );

      // The request failed, but nothing proved the token invalid beyond this
      // one call — discarding it would force a re-login the user can't avoid.
      expect(await client.tokens.accessToken, 'access-1');
    });

    test('no refresh call is attempted when there is nothing to refresh with',
        () async {
      final adapter = _ScriptedAdapter((_) => _json('{"error":"expired"}', 401));
      final client = buildClient(
        adapter: adapter,
        tokens: {'streamio.access_token': 'access-1'},
      );

      await expectLater(
        client.get<Map<String, dynamic>>('/api/account/me', authenticated: true),
        throwsA(isA<SessionExpiredException>()),
      );

      expect(
        adapter.requests.map((request) => request.path),
        isNot(contains('/api/auth/refresh')),
      );
    });
  });

  group('errors', () {
    test('surface the server\'s own message', () async {
      final adapter =
          _ScriptedAdapter((_) => _json('{"error":"Invalid email or password."}', 401));
      final client = buildClient(adapter: adapter);

      await expectLater(
        client.post<Map<String, dynamic>>('/api/auth/login', body: {}),
        throwsA(isA<ApiException>().having(
            (err) => err.message, 'message', 'Invalid email or password.')),
      );
    });
  });

  group('url helpers', () {
    test('build absolute and websocket URLs from the base', () {
      final client = buildClient(adapter: _ScriptedAdapter((_) => _json('{}', 200)));

      expect(client.absolute('/api/home'), 'https://streamio.example/api/home');
      expect(client.absolute('https://elsewhere/x'), 'https://elsewhere/x');
      expect(client.webSocketUrl('/ws/rooms/AB3C9K'),
          'wss://streamio.example/ws/rooms/AB3C9K');
    });
  });

  // dart:io auto-follows redirects for GET/HEAD only, so without explicit
  // handling every write surfaced the 3xx as "Request failed (HTTP 302)".
  // The `redirect/` tunnel in front of a Streamio install redirects by
  // design, so this is the normal path, not an edge case.
  group('redirects', () {
    test('a POST is replayed at the Location, keeping method and body',
        () async {
      final adapter = _ScriptedAdapter((options) {
        if (options.uri.host == 'streamio.ddns.net') {
          return _redirect('https://tunnel.example/api/auth/login');
        }
        return _json('{"access_token":"a","refresh_token":"r"}', 200);
      });

      final client = buildClient(
          adapter: adapter, baseUrl: 'https://streamio.ddns.net');

      final result = await client.post<Map<String, dynamic>>(
        '/api/auth/login',
        body: {'email': 'a@b.c', 'password': 'secret'},
      );

      expect(result['access_token'], 'a');
      expect(adapter.requests, hasLength(2));

      final replay = adapter.requests.last;
      expect(replay.uri.toString(), 'https://tunnel.example/api/auth/login');
      // A browser would downgrade a 302'd POST to a bodyless GET, which for
      // an API call just fails.
      expect(replay.method, 'POST');
      expect((replay.data as Map)['password'], 'secret');
    });

    test('DELETE and PUT are followed too', () async {
      for (final method in ['DELETE', 'PUT']) {
        final adapter = _ScriptedAdapter((options) {
          if (options.uri.host == 'streamio.ddns.net') {
            return _redirect('https://tunnel.example/api/account/watchlist/p/s');
          }
          return _json('{"ok":true}', 200);
        });
        final client = buildClient(
            adapter: adapter, baseUrl: 'https://streamio.ddns.net');

        if (method == 'DELETE') {
          await client.delete<Map<String, dynamic>>('/api/account/watchlist/p/s');
        } else {
          await client.put<Map<String, dynamic>>('/api/account/ratings/p/s',
              body: {'rating': 8});
        }

        expect(adapter.requests.last.method, method, reason: method);
        expect(adapter.requests.last.uri.host, 'tunnel.example', reason: method);
      }
    });

    test('carries the bearer token across the hop', () async {
      final adapter = _ScriptedAdapter((options) {
        if (options.uri.host == 'streamio.ddns.net') {
          return _redirect('https://tunnel.example/api/account/history');
        }
        return _json('{"ok":true}', 200);
      });

      final client = buildClient(
        adapter: adapter,
        baseUrl: 'https://streamio.ddns.net',
        tokens: {
          'streamio.access_token': 'access-1',
          'streamio.refresh_token': 'refresh-1',
        },
      );

      await client.post<Map<String, dynamic>>('/api/account/history',
          body: {'progress_seconds': 12}, authenticated: true);

      expect(adapter.requests.last.headers['Authorization'], 'Bearer access-1');
    });

    test('drops the token when a redirect downgrades to http', () async {
      final adapter = _ScriptedAdapter((options) {
        if (options.uri.scheme == 'https') {
          return _redirect('http://insecure.example/api/account/history');
        }
        return _json('{"ok":true}', 200);
      });

      final client = buildClient(
        adapter: adapter,
        baseUrl: 'https://streamio.ddns.net',
        tokens: {
          'streamio.access_token': 'access-1',
          'streamio.refresh_token': 'refresh-1',
        },
      );

      await client.post<Map<String, dynamic>>('/api/account/history',
          body: {'progress_seconds': 12}, authenticated: true);

      // A downgrade is a misconfiguration or an attack; neither gets the token.
      expect(adapter.requests.last.uri.scheme, 'http');
      expect(adapter.requests.last.headers.containsKey('Authorization'), isFalse);
    });

    test('gives up on a redirect loop with a message naming the target',
        () async {
      final adapter = _ScriptedAdapter(
          (_) => _redirect('https://streamio.ddns.net/api/home'));
      final client = buildClient(
          adapter: adapter, baseUrl: 'https://streamio.ddns.net');

      await expectLater(
        client.post<Map<String, dynamic>>('/api/home'),
        throwsA(isA<ApiException>().having((err) => err.message, 'message',
            contains('https://streamio.ddns.net/api/home'))),
      );
      // Bounded, not infinite.
      expect(adapter.requests.length, lessThanOrEqualTo(7));
    });
  });

  // An install behind a reverse proxy is often mounted under a path
  // (https://streamio.ddns.net/streamio). Every request has to keep that
  // prefix — including the ones Dio composes from baseUrl + path, which is
  // string concatenation rather than Uri.resolve and worth pinning down.
  group('path-prefixed server', () {
    const base = 'https://streamio.ddns.net/streamio';

    test('requests keep the prefix', () async {
      final adapter = _ScriptedAdapter((_) => _json('{"data":[]}', 200));
      final client = buildClient(adapter: adapter, baseUrl: base);

      await client.get<Map<String, dynamic>>('/api/home');

      expect(adapter.requests.single.uri.toString(),
          'https://streamio.ddns.net/streamio/api/home');
    });

    test('a refresh keeps the prefix too', () async {
      final adapter = _ScriptedAdapter((options) {
        if (options.path == '/api/auth/refresh') {
          return _json('{"access_token":"access-2"}', 200);
        }
        return options.headers['Authorization'] == 'Bearer access-2'
            ? _json('{"ok":true}', 200)
            : _json('{"error":"expired"}', 401);
      });

      final client = buildClient(
        adapter: adapter,
        baseUrl: base,
        tokens: {
          'streamio.access_token': 'access-1',
          'streamio.refresh_token': 'refresh-1',
        },
      );

      await client.get<Map<String, dynamic>>('/api/account/me', authenticated: true);

      expect(
        adapter.requests.map((request) => request.uri.toString()),
        contains('https://streamio.ddns.net/streamio/api/auth/refresh'),
      );
    });

    test('absolute and websocket URLs keep the prefix', () {
      final client = buildClient(
          adapter: _ScriptedAdapter((_) => _json('{}', 200)), baseUrl: base);

      expect(client.absolute('/api/cast-proxy?url=x'),
          'https://streamio.ddns.net/streamio/api/cast-proxy?url=x');
      expect(client.webSocketUrl('/ws/rooms/AB3C9K'),
          'wss://streamio.ddns.net/streamio/ws/rooms/AB3C9K');
    });
  });

  // The host is powered down when idle and the `redirect/` tunnel in front of
  // it answers 200 with a static waiting page until it is back. Sitting in the
  // player is the app's longest stretch without API traffic, so the next menu
  // refresh is where this lands.
  group('a server that answers with its waiting page', () {
    test('retries a GET and succeeds once the server is up', () async {
      var calls = 0;
      final adapter = _ScriptedAdapter((_) {
        calls++;
        return calls == 1
            ? _html(_waitingPage)
            : _json('{"data":[{"name":"Featured"}]}', 200);
      });
      final client = buildClient(adapter: adapter);

      final result = await client.get<Map<String, dynamic>>('/api/home');

      expect(result['data'], hasLength(1));
      expect(calls, 2);
    });

    test('gives up with a message naming the cause, not "not JSON"', () async {
      final adapter = _ScriptedAdapter((_) => _html(_waitingPage));
      final client = buildClient(adapter: adapter);

      await expectLater(
        client.get<Map<String, dynamic>>('/api/home'),
        throwsA(isA<ServerNotReadyException>().having(
          (err) => err.message,
          'message',
          allOf(contains('starting up'), isNot(contains('JSON'))),
        )),
      );
      // The initial attempt plus the two backoff retries.
      expect(adapter.requests, hasLength(3));
    });

    test('does not retry a write, which may not be idempotent', () async {
      final adapter = _ScriptedAdapter((_) => _html(_waitingPage));
      final client = buildClient(adapter: adapter);

      await expectLater(
        client.post<Map<String, dynamic>>('/api/account/history'),
        throwsA(isA<ServerNotReadyException>()),
      );
      expect(adapter.requests, hasLength(1));
    });

    // It says nothing about the session, so it must not cost the user their
    // login the way a 401 would.
    test('leaves the stored session alone', () async {
      final adapter = _ScriptedAdapter((_) => _html(_waitingPage));
      final client = buildClient(
        adapter: adapter,
        tokens: {
          'streamio.access_token': 'access-1',
          'streamio.refresh_token': 'refresh-1',
        },
      );

      await expectLater(
        client.get<Map<String, dynamic>>('/api/home', authenticated: true),
        throwsA(isA<ServerNotReadyException>()),
      );
      expect(await client.tokens.accessToken, 'access-1');
      expect(await client.tokens.refreshToken, 'refresh-1');
    });
  });

  group('empty bodies', () {
    test('a 204 is no content, not malformed JSON', () async {
      final adapter = _ScriptedAdapter(
          (_) => ResponseBody.fromString('', 204, headers: {}));
      final client = buildClient(adapter: adapter);

      await expectLater(
          client.delete<void>('/api/account/history'), completes);
    });

    test('an empty body where data was expected says so', () async {
      final adapter = _ScriptedAdapter(
          (_) => ResponseBody.fromString('', 200, headers: {}));
      final client = buildClient(adapter: adapter);

      await expectLater(
        client.get<Map<String, dynamic>>('/api/home'),
        throwsA(isA<ApiException>().having(
          (err) => err.message,
          'message',
          contains('empty'),
        )),
      );
    });
  });
}
