import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamio/core/api/api_client.dart';
import 'package:streamio/core/api/auth_api.dart';
import 'package:streamio/core/api/token_store.dart';

/// The TV sign-in flow (`POST /api/auth/device/*`, `../web/auth/deviceLogin.ts`).
///
/// Every case here is one the screen cannot tell apart on its own: the poll
/// answers 200 whether it is still waiting or has just handed over a session,
/// and a code running out arrives as a 410 that would otherwise read as a
/// transport failure. Getting any of them wrong strands a user in front of a
/// television with no way to notice.
class _MemoryStorage extends FlutterSecureStorage {
  _MemoryStorage([Map<String, String>? initial]) : _values = {...?initial};

  final Map<String, String> _values;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
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
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _values.remove(key);
}

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ({AuthApi api, TokenStore tokens, _ScriptedAdapter adapter}) build(
    ResponseBody Function(RequestOptions options) handler,
  ) {
    final adapter = _ScriptedAdapter(handler);
    final tokens = TokenStore(storage: _MemoryStorage());
    final client = ApiClient(
      baseUrl: 'https://streamio.example',
      tokens: tokens,
      dio: Dio()..httpClientAdapter = adapter,
    );
    return (api: AuthApi(client), tokens: tokens, adapter: adapter);
  }

  const startBody = '''
{"user_code":"K7RQ-4M3P","device_code":"dev-secret",
 "verification_uri":"https://streamio.example/tv",
 "verification_uri_complete":"https://streamio.example/tv?code=K7RQ-4M3P",
 "expires_in":600,"interval":5}''';

  Future<DeviceLoginSession> start(AuthApi api) => api.startDeviceLogin();

  group('starting a TV sign-in', () {
    test('reads the code, the URL to show and the polling interval', () async {
      final h = build((_) => _json(startBody, 200));

      final session = await start(h.api);

      expect(session.userCode, 'K7RQ-4M3P');
      expect(session.deviceCode, 'dev-secret');
      expect(session.verificationUri, 'https://streamio.example/tv');
      expect(session.verificationUriComplete,
          'https://streamio.example/tv?code=K7RQ-4M3P');
      expect(session.interval, const Duration(seconds: 5));
      expect(session.expiresIn, const Duration(minutes: 10));
    });

    test('falls back to the bare URL when the server sends no prefilled one',
        () async {
      final h = build((_) => _json(
          '{"user_code":"AAAA-BBBB","device_code":"d",'
          '"verification_uri":"https://streamio.example/tv"}',
          200));

      final session = await start(h.api);

      // The QR encodes this; pointing it at nothing would be a blank square.
      expect(session.verificationUriComplete, 'https://streamio.example/tv');
      // Defaults, so a server predating these fields still polls sanely
      // instead of every 0 seconds.
      expect(session.interval, const Duration(seconds: 5));
      expect(session.expiresIn, const Duration(minutes: 10));
    });

    test('a response with no code is an error, not an empty screen', () async {
      final h = build((_) => _json('{"expires_in":600}', 200));

      expect(start(h.api), throwsA(isA<ApiException>()));
    });
  });

  group('polling', () {
    test('reports pending without touching the keystore', () async {
      final h = build((options) => options.path.endsWith('/device/start')
          ? _json(startBody, 200)
          : _json('{"status":"pending"}', 200));

      final session = await start(h.api);
      final status = await h.api.pollDeviceLogin(session);

      expect(status, DeviceLoginStatus.pending);
      expect(await h.tokens.accessToken, isNull);
    });

    test('sends both codes, since the user code alone proves nothing',
        () async {
      final h = build((options) => options.path.endsWith('/device/start')
          ? _json(startBody, 200)
          : _json('{"status":"pending"}', 200));

      final session = await start(h.api);
      await h.api.pollDeviceLogin(session);

      final poll = h.adapter.requests.last;
      expect(poll.path, contains('/api/auth/device/token'));
      expect(poll.data, {'device_code': 'dev-secret', 'user_code': 'K7RQ-4M3P'});
    });

    test('an approved poll saves the session', () async {
      final h = build((options) => options.path.endsWith('/device/start')
          ? _json(startBody, 200)
          : _json(
              '{"status":"approved","access_token":"access-1",'
              '"refresh_token":"refresh-1"}',
              200));

      final session = await start(h.api);
      final status = await h.api.pollDeviceLogin(session);

      expect(status, DeviceLoginStatus.approved);
      // Both, not just the access token: a native client has no cookie jar, so
      // dropping the refresh token here would sign the TV out again in 15 min.
      expect(await h.tokens.accessToken, 'access-1');
      expect(await h.tokens.refreshToken, 'refresh-1');
    });

    test('a 410 is the code expiring, not a failure', () async {
      final h = build((options) => options.path.endsWith('/device/start')
          ? _json(startBody, 200)
          : _json('{"status":"expired","error":"This sign-in code has expired."}',
              410));

      final session = await start(h.api);

      // Reported rather than thrown: the screen answers it by offering a new
      // code, which a generic error banner would not.
      expect(await h.api.pollDeviceLogin(session), DeviceLoginStatus.expired);
    });

    test('a rejected device code still throws', () async {
      final h = build((options) => options.path.endsWith('/device/start')
          ? _json(startBody, 200)
          : _json('{"error":"Invalid device code."}', 403));

      final session = await start(h.api);

      expect(h.api.pollDeviceLogin(session), throwsA(isA<ApiException>()));
    });
  });
}
