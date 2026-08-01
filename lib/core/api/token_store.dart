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
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
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
    _access = await _storage.read(key: _accessKey);
    _refresh = await _storage.read(key: _refreshKey);
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
