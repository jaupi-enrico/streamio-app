import 'api_client.dart';

/// A TV sign-in in progress — `POST /api/auth/device/start`.
///
/// [userCode] is what goes on the screen; [deviceCode] is the secret this
/// device proves to collect the session and must never be displayed. See
/// `../web/auth/deviceLogin.ts` for why the two are split.
class DeviceLoginSession {
  const DeviceLoginSession({
    required this.userCode,
    required this.deviceCode,
    required this.verificationUri,
    required this.verificationUriComplete,
    required this.expiresIn,
    required this.interval,
  });

  final String userCode;
  final String deviceCode;

  /// The address a user types on their phone, e.g. `https://host/streamio/tv`.
  final String verificationUri;

  /// The same page with `?code=` filled in — what the QR code encodes.
  final String verificationUriComplete;

  final Duration expiresIn;

  /// How long the server asks us to wait between polls.
  final Duration interval;

  factory DeviceLoginSession.fromJson(Map<String, dynamic> json) {
    final userCode = json['user_code']?.toString();
    final deviceCode = json['device_code']?.toString();
    final verificationUri = json['verification_uri']?.toString();

    if (userCode == null || deviceCode == null || verificationUri == null) {
      throw const ApiException('The server did not return a sign-in code.');
    }

    return DeviceLoginSession(
      userCode: userCode,
      deviceCode: deviceCode,
      verificationUri: verificationUri,
      verificationUriComplete:
          json['verification_uri_complete']?.toString() ?? verificationUri,
      expiresIn: Duration(
          seconds: (json['expires_in'] as num?)?.toInt() ?? 600),
      interval: Duration(seconds: (json['interval'] as num?)?.toInt() ?? 5),
    );
  }
}

/// Where a [DeviceLoginSession] stands. Anything else the poll can return is
/// an error and throws.
enum DeviceLoginStatus {
  /// Nobody has approved it yet. Keep polling.
  pending,

  /// Approved, and the tokens are now in the keystore.
  approved,

  /// The code ran out or was already used. Start over with a fresh one.
  expired,
}

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

  /// Starts a TV sign-in and returns the code to put on screen.
  ///
  /// This is the path for devices that cannot open a browser at all — an
  /// Android TV typically has no `https` handler installed, so the Custom Tab
  /// the normal OAuth path opens has nothing to launch it and the flow can
  /// never begin. [label] is shown on the approval page so they can see
  /// what they are signing in.
  Future<DeviceLoginSession> startDeviceLogin({String? label}) async {
    final json = await _client.post<Map<String, dynamic>>(
      '/api/auth/device/start',
      body: {if (label != null && label.isNotEmpty) 'label': label},
    );
    return DeviceLoginSession.fromJson(json);
  }

  /// Asks whether [session] has been approved yet, saving the tokens if it has.
  ///
  /// The server answers 200 for both "still waiting" and "here is your
  /// session", so a thrown [ApiException] here really is a failure — except
  /// 410, which is the code expiring and is reported as
  /// [DeviceLoginStatus.expired] rather than thrown, since it is an expected
  /// end state for a code nobody got round to approving.
  Future<DeviceLoginStatus> pollDeviceLogin(DeviceLoginSession session) async {
    Map<String, dynamic> json;
    try {
      json = await _client.post<Map<String, dynamic>>(
        '/api/auth/device/token',
        body: {
          'device_code': session.deviceCode,
          'user_code': session.userCode,
        },
      );
    } on ApiException catch (err) {
      if (err.statusCode == 410) return DeviceLoginStatus.expired;
      rethrow;
    }

    if (json['status'] == 'pending') return DeviceLoginStatus.pending;

    await _saveTokens(json);
    return DeviceLoginStatus.approved;
  }

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
