import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamio/core/api/api_client.dart';
import 'package:streamio/core/api/content_api.dart';
import 'package:streamio/core/api/token_store.dart';

/// `/api/genres` and `/api/genres/:id` return different things, and confusing
/// them is silent: the catalogue's entries parse perfectly well, they just
/// carry no shows — so a genre browse reading them renders an empty grid and
/// looks like a genre with nothing in it. These pin the two apart.

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

  group('genre browse', () {
    test('asks the per-genre route, not the catalogue', () async {
      final adapter = _ScriptedAdapter(
        (_) => _json('{"provider":"filmhub","page":1,'
            '"data":{"id":"12","name":"Azione","shows":[]}}'),
      );

      await buildApi(adapter)
          .genre('12', provider: 'filmhub', page: 1);

      final request = adapter.requests.single;
      expect(request.path, '/api/genres/12');
      expect(request.queryParameters['provider'], 'filmhub');
      expect(request.queryParameters['page'], 1);
    });

    test('reads the titles off data.shows', () async {
      final adapter = _ScriptedAdapter(
        (_) => _json('{"provider":"filmhub","page":1,"data":{'
            '"id":"12","name":"Azione","shows":['
            '{"id":"1","title":"One","seasons":[]},'
            '{"id":"2","title":"Two"}]}}'),
      );

      final genre = await buildApi(adapter).genre('12');

      expect(genre.id, '12');
      expect(genre.name, 'Azione');
      expect(genre.shows.map((s) => s.title), ['One', 'Two']);
    });

    test('percent-encodes an id that is a group name, as the IPTV providers use',
        () async {
      final adapter = _ScriptedAdapter(
        (_) => _json('{"data":{"id":"News/Sport","name":"News","shows":[]}}'),
      );

      await buildApi(adapter).genre('News/Sport');

      // Unencoded, the slash would split into a path segment and 404.
      expect(adapter.requests.single.path, '/api/genres/News%2FSport');
    });

    test('an empty page is a real answer, not a parse failure', () async {
      final adapter = _ScriptedAdapter(
        (_) => _json('{"provider":"livegrid","page":9,'
            '"data":{"id":"12","name":"Azione","shows":[]}}'),
      );

      final genre = await buildApi(adapter).genre('12', page: 9);

      expect(genre.shows, isEmpty);
      expect(genre.name, 'Azione');
    });

    test('the catalogue route carries no shows — which is why it is not the '
        'browse', () async {
      final adapter = _ScriptedAdapter(
        (_) => _json('{"provider":"filmhub","supported":true,'
            '"data":[{"id":"12","name":"Azione"},{"id":"13","name":"Commedia"}]}'),
      );

      final genres = await buildApi(adapter).genres();

      expect(genres.map((g) => g.name), ['Azione', 'Commedia']);
      expect(genres.every((g) => g.shows.isEmpty), isTrue);
    });

    test('a provider without a genre filter answers an empty catalogue, '
        'not an error', () async {
      final adapter = _ScriptedAdapter(
        (_) => _json('{"provider":"livegrid","supported":false,"data":[]}'),
      );

      expect(await buildApi(adapter).genres(), isEmpty);
    });

    test('the backend refusing a browse surfaces its own wording', () async {
      final adapter = _ScriptedAdapter(
        (_) => _json(
            '{"error":"Provider \\"livegrid\\" does not support genre '
            'browsing"}',
            400),
      );

      await expectLater(
        buildApi(adapter).genre('12', provider: 'livegrid'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.message, 'message', contains('genre browsing'))),
      );
    });

    test('an 18+ genre behind a closed gate is a 403 the UI can show',
        () async {
      final adapter = _ScriptedAdapter(
        (_) => _json('{"error":"Adult content is disabled"}', 403),
      );

      await expectLater(
        buildApi(adapter).genre('99'),
        throwsA(isA<ApiException>().having((e) => e.isForbidden, 'isForbidden', isTrue)),
      );
    });
  });
}
