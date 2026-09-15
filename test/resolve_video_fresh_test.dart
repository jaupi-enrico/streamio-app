import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamio/core/api/api_client.dart';
import 'package:streamio/core/api/content_api.dart';
import 'package:streamio/core/api/token_store.dart';
import 'package:streamio/core/models/models.dart';
import 'package:streamio/features/watch/watch_providers.dart';

/// `fresh=1` is what makes a playback retry mean anything.
///
/// The backend caches a resolve (`PlatformHandler.resolveVideo`), and the
/// resolved URLs are signed and die in minutes. So when playback fails —
/// `tcp: ffurl_read returned 0xdfb9b0bb`, i.e. the connection ended — a retry
/// that omits the flag is handed back the *identical dead URL* for the rest of
/// the cache's TTL and fails in exactly the same way, five times over. Nothing
/// about that is visible: the request succeeds, the payload parses, the stream
/// just doesn't play. Hence a test on the query string rather than on
/// behaviour.
///
/// The counterpart is `retryCurrentStream()` in
/// `../web/public/scripts/watch.js`, which has passed the flag since it was
/// added server-side.

class _MemoryStorage extends FlutterSecureStorage {
  _MemoryStorage() : super();

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
      null;
}

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body, [int statusCode = 200]) =>
    ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

const _server = VideoServer(id: '1', name: 'Primary CDN', src: 'https://x/1');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ContentApi buildApi(_ScriptedAdapter adapter) {
    final dio = Dio()..httpClientAdapter = adapter;
    return ContentApi(ApiClient(
      baseUrl: 'https://streamio.example',
      tokens: TokenStore(storage: _MemoryStorage()),
      dio: dio,
    ));
  }

  _ScriptedAdapter resolvingAdapter() => _ScriptedAdapter(
        (_) => _json('{"data":{"playlistUrl":"https://cdn/p.m3u8"}}'),
      );

  group('resolveVideo', () {
    test('a normal playback attempt may be served from the resolve cache',
        () async {
      final adapter = resolvingAdapter();
      await buildApi(adapter).resolveVideo('ep-1', _server);

      expect(adapter.requests.single.uri.queryParameters,
          isNot(contains('fresh')));
    });

    test('a retry after a failure bypasses the resolve cache', () async {
      final adapter = resolvingAdapter();
      await buildApi(adapter).resolveVideo('ep-1', _server, fresh: true);

      expect(adapter.requests.single.uri.queryParameters['fresh'], '1');
    });

    test('the flag survives the resolvePlayback wrapper the player calls',
        () async {
      final adapter = resolvingAdapter();
      await resolvePlayback(
        buildApi(adapter),
        'filmhub',
        'ep-1',
        knownServers: const [_server],
        fresh: true,
      );

      // Only the resolve went out: a retry reuses the server list it already
      // has rather than paying for /servers again.
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.uri.queryParameters['fresh'], '1');
    });
  });
}
