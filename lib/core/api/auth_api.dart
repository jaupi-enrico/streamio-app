import 'api_client.dart';

/// `routes/auth.router.ts`. Every token-issuing call here persists both
/// tokens through [ApiClient.tokens]; the backend includes the refresh token
/// in the body because the client sends `X-Client: app`.
class AuthApi {
  AuthApi(this._client);

  final ApiClient _client;

  /// The custom scheme registered in AndroidManifest.xml / Info.plist. The
  /// backend only redirects to allowlisted targets, and this is the one it
  /// allows for native clients.
  static const oauthRedirectUri = 'streamio://auth';

  Future<void> register(String email, String password,
      {String? displayName}) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/api/auth/register',
      body: {
        'email': email,
        'password': password,
        if (displayName != null && displayName.isNotEmpty)
          'display_name': displayName,
      },
    );
    await _saveTokens(json);
  }

  Future<void> login(String email, String password) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/api/auth/login',
      body: {'email': email, 'password': password},
    );
    await _saveTokens(json);
  }

  Future<void> logout() async {
    final refreshToken = await _client.tokens.refreshToken;
    try {
      await _client.post<dynamic>(
        '/api/auth/logout',
        body: {if (refreshToken != null) 'refresh_token': refreshToken},
      );
    } catch (_) {
      // A failed revoke server-side must not strand the user in a
      // logged-in-looking state; the local tokens go either way.
    }
    await _client.tokens.clear();
  }

  /// Consumes the token from the verification email.
  Future<void> verifyEmail(String token) => _client.post<dynamic>(
        '/api/auth/verify-email',
        body: {'token': token},
      );

  Future<void> requestPasswordReset(String email) => _client.post<dynamic>(
        '/api/auth/password-reset/request',
        body: {'email': email},
      );

  Future<void> confirmPasswordReset(String token, String password) =>
      _client.post<dynamic>(
        '/api/auth/password-reset/confirm',
        body: {'token': token, 'password': password},
      );

  /// The URL to open in a browser tab for OAuth. The backend redirects back
  /// to [oauthRedirectUri] with `?token=&refresh=`.
  String oauthUrl(String provider) => Uri.parse(_client.absolute('/api/auth/$provider'))
      .replace(queryParameters: {'redirect_uri': oauthRedirectUri})
      .toString();

  /// Consumes the `streamio://auth?token=...&refresh=...` callback.
  Future<bool> completeOAuth(Uri callback) async {
    final access = callback.queryParameters['token'];
    final refresh = callback.queryParameters['refresh'];
    if (access == null || access.isEmpty) return false;
    await _client.tokens.save(accessToken: access, refreshToken: refresh);
    return true;
  }

  Future<void> _saveTokens(Map<String, dynamic> json) async {
    final access = json['access_token']?.toString();
    final refresh = json['refresh_token']?.toString();
    if (access == null) {
      throw const ApiException('The server did not return an access token.');
    }
    await _client.tokens.save(accessToken: access, refreshToken: refresh);
  }
}
