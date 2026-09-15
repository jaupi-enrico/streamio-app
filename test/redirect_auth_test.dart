import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamio/core/api/api_client.dart';
import 'package:streamio/core/api/token_store.dart';

/// Redirect handling against **real** HTTP servers rather than a mocked
/// adapter, because the bug this guards against lives in `dart:io` itself and
/// a fake adapter cannot reproduce it.
///
/// A Streamio install is typically reached through a hostname that redirects
/// to whatever address is actually serving it, so essentially every request is
/// a cross-host redirect. `dart:io`'s automatic redirect following **drops
/// the Authorization header** on that hop, so an authenticated request arrives
/// anonymous, 401s, and the session looks expired. [ApiClient] therefore
/// disables auto-follow and replays redirects itself.
class _MemoryStorage extends FlutterSecureStorage {
  _MemoryStorage(this._values) : super();

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

void main() {
  late HttpServer origin;
  late HttpServer target;

  // What the far side of the redirect actually received.
  String? seenAuth;
  String? seenMethod;
  String? seenBody;
  var reachedTarget = false;

  setUp(() async {
    seenAuth = null;
    seenMethod = null;
    seenBody = null;
    reachedTarget = false;

    // Stands in for the server itself: records the request and answers.
    target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    target.listen((request) async {
      reachedTarget = true;
      seenAuth = request.headers.value('authorization');
      seenMethod = request.method;
      seenBody = await utf8.decodeStream(request);

      request.response
        ..statusCode = seenAuth == null ? 401 : 200
        ..headers.contentType = ContentType.json
        ..write(seenAuth == null
            ? '{"error":"Unauthorized"}'
            : '{"id":"u1","email":"a@b.c"}');
      await request.response.close();
    });

    // Stands in for the entry host: redirects everything to the "server",
    // on a different port and therefore a different origin.
    origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin.listen((request) async {
      request.response
        ..statusCode = 302
        ..headers.set(
            'location', 'http://127.0.0.1:${target.port}${request.uri.path}');
      await request.response.close();
    });
  });

  tearDown(() async {
    await origin.close(force: true);
    await target.close(force: true);
  });

  ApiClient buildClient() => ApiClient(
        baseUrl: 'http://127.0.0.1:${origin.port}',
        tokens: TokenStore(
          storage: _MemoryStorage({
            'streamio.access_token': 'access-1',
            'streamio.refresh_token': 'refresh-1',
          }),
        ),
      );

  test('an authenticated GET keeps its bearer token across the redirect',
      () async {
    final client = buildClient();

    final result = await client
        .get<Map<String, dynamic>>('/api/account/me', authenticated: true);

    expect(reachedTarget, isTrue);
    // The regression: dart:io's own redirect following delivers this as null,
    // the target answers 401, and the session is discarded as expired.
    expect(seenAuth, 'Bearer access-1');
    expect(result['id'], 'u1');

    client.dispose();
  });

  test('a POST keeps its method and body across the redirect', () async {
    final client = buildClient();

    await client.post<Map<String, dynamic>>(
      '/api/account/history',
      body: {'progress_seconds': 42},
      authenticated: true,
    );

    expect(seenMethod, 'POST');
    expect(jsonDecode(seenBody!)['progress_seconds'], 42);
    expect(seenAuth, 'Bearer access-1');

    client.dispose();
  });

  test('an unauthenticated request is still followed', () async {
    final client = buildClient();

    // No token attached, so the target answers 401 — what matters is that the
    // hop happened at all.
    await expectLater(
      client.get<Map<String, dynamic>>('/api/home'),
      throwsA(isA<ApiException>()),
    );
    expect(reachedTarget, isTrue);

    client.dispose();
  });
}
