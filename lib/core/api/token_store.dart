import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Access + refresh tokens, in the platform keystore/keychain.
///
/// The web frontend keeps the access token in `sessionStorage` and leaves the
/// refresh token to the browser's cookie jar (`public/scripts/auth.js`). A
/// native client has neither, which is why the backend hands app clients the
/// refresh token in the JSON body when they send `X-Client: app` (see
/// `sendTokens` in `web/routes/auth.router.ts`). Both tokens are held here.
class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            // `encryptedSharedPreferences` is gone as of flutter_secure_storage
            // 10 — the Jetpack Security backend it selected is deprecated by
            // Google — and the defaults here (AES-GCM data under an RSA-OAEP
            // wrapped keystore key) migrate anything an older build wrote on
            // first access. `migrateWithBackup` keeps a copy while that runs so
            // a crash mid-migration doesn't strand a signed-in user at /login.
            const FlutterSecureStorage(
              aOptions: AndroidOptions(migrateWithBackup: true),
            );

  static const _accessKey = 'streamio.access_token';
  static const _refreshKey = 'streamio.refresh_token';
  static const _userKey = 'streamio.cached_user';

  final FlutterSecureStorage _storage;

  // Cached in memory so the hot path (an Authorization header on every
  // request) doesn't hit the keystore each time.
  String? _access;
  String? _refresh;
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      _access = await _storage.read(key: _accessKey);
      _refresh = await _storage.read(key: _refreshKey);
    } catch (err, stack) {
      // A keystore read failure (corrupt/undecryptable entry, plugin error)
      // otherwise looks identical to "never logged in" to every caller here.
      developer.log('keystore read failed', name: 'auth', error: err, stackTrace: stack);
      rethrow;
    }
    _loaded = true;
  }

  /// The last profile `/api/account/me` returned, as raw JSON.
  ///
  /// Every screen now needs a signed-in user, so a launch with no network
  /// would otherwise strand someone with a perfectly good session — and their
  /// offline downloads with them. This is what the session is restored from
  /// when the profile fetch fails for a reason that isn't "signed out".
  Future<String?> get cachedUser => _storage.read(key: _userKey);

  Future<void> saveCachedUser(String json) =>
      _storage.write(key: _userKey, value: json);

  Future<String?> get accessToken async {
    await _ensureLoaded();
    return _access;
  }

  Future<String?> get refreshToken async {
    await _ensureLoaded();
    return _refresh;
  }

  /// Whether the stored access token is present and not about to expire,
  /// read from the JWT's own `exp` claim.
  ///
  /// This exists for the `optionalAuth` routes, which are the only ones where
  /// an expired token fails *silently*: `optionalAuth` in
  /// `../web/auth/middleware.ts` catches the verification error and serves the
  /// request as a guest, so a stale token doesn't 401 — the response simply
  /// comes back de-personalised, with the 18+ gates shut. There is no status
  /// code to react to, so freshness has to be known before the request goes
  /// out. Authenticated routes use it too, to skip burning a 401 on a token
  /// already known to be dead.
  ///
  /// A token that doesn't decode as a JWT counts as fresh: this is a hint for
  /// choosing when to refresh, not an authority on validity — the server is
  /// that — and answering "stale" would refresh before every single request.
  Future<bool> get hasFreshAccessToken async {
    final token = await accessToken;
    if (token == null) return false;

    final expiry = _expiryOf(token);
    if (expiry == null) return true;
    return DateTime.now().toUtc().add(_expirySkew).isBefore(expiry);
  }

  /// Refresh this long before the token actually expires, so a request that is
  /// in flight across the boundary — or a clock a little out of step with the
  /// server's — doesn't land as an anonymous one.
  static const _expirySkew = Duration(seconds: 30);

  /// The `exp` claim, or null if this isn't a JWT with a usable one.
  static DateTime? _expiryOf(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final exp = payload is Map ? payload['exp'] : null;
      if (exp is! num) return null;
      return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000,
          isUtc: true);
    } catch (_) {
      return null;
    }
  }

  /// True when there is anything to authenticate with.
  ///
  /// Either token counts. A refresh token alone can mint a new access token;
  /// an access token alone is still a usable session until it expires. Only
  /// requiring the refresh token would report "signed out" while a working
  /// session is sitting in the keystore.
  Future<bool> get hasSession async =>
      (await refreshToken) != null || (await accessToken) != null;

  Future<void> save({String? accessToken, String? refreshToken}) async {
    await _ensureLoaded();
    if (accessToken != null) {
      _access = accessToken;
      await _storage.write(key: _accessKey, value: accessToken);
    }
    if (refreshToken != null) {
      _refresh = refreshToken;
      await _storage.write(key: _refreshKey, value: refreshToken);
    }
  }

  Future<void> clear() async {
    _access = null;
    _refresh = null;
    _loaded = true;
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _userKey);
  }
}
