import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamio/core/api/api_client.dart';
import 'package:streamio/core/api/token_store.dart';

/// The account listings kept a bare JSON array and put their paging numbers in
/// headers, so everything that can go wrong here is silent: a wrong offset
/// duplicates rows rather than throwing, and an old server that ignores
/// `limit` looks exactly like a full page.
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
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _list(List<Map<String, dynamic>> rows,
        {Map<String, String> headers = const {}}) =>
    ResponseBody.fromString(
      jsonEncode(rows),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        for (final entry in headers.entries) entry.key: [entry.value],
      },
    );

Map<String, dynamic> _row(int i) => {'provider': 'sc', 'show_id': '$i'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ApiClient buildClient(_ScriptedAdapter adapter) => ApiClient(
        baseUrl: 'https://streamio.example',
        tokens: TokenStore(storage: _MemoryStorage()),
        dio: Dio()..httpClientAdapter = adapter,
      );

  Future<dynamic> fetch(_ScriptedAdapter adapter) => buildClient(adapter)
      .getPaged<String>('/api/account/watchlist',
          (json) => json['show_id'].toString());

  test('reads both paging headers', () async {
    final page = await fetch(_ScriptedAdapter((_) => _list(
          [_row(1), _row(2)],
          headers: {'X-Total-Count': '87', 'X-Page-Rows': '24'},
        )));

    expect(page.total, 87);
    expect(page.pageRows, 24);
    expect(page.paged, isTrue);
    expect(page.items, ['1', '2']);
  });

  test('advances by X-Page-Rows even when the 18+ gate shortened the page',
      () async {
    // The server read 24 rows and filtered 3 away before sending. Paging by
    // the array length would re-request those 3 and serve the survivors twice.
    final page = await fetch(_ScriptedAdapter((_) => _list(
          [for (var i = 0; i < 21; i++) _row(i)],
          headers: {'X-Total-Count': '90', 'X-Page-Rows': '24'},
        )));

    expect(page.items, hasLength(21));
    expect(page.pageRows, 24, reason: 'the offset advances by what was read');
  });

  test('a server that sends no headers is not paging', () async {
    // The pre-paging endpoints ignore limit/offset and answer with the whole
    // listing. Trusting the arithmetic here would page forever through the
    // same rows.
    final page = await fetch(_ScriptedAdapter(
        (_) => _list([for (var i = 0; i < 87; i++) _row(i)])));

    expect(page.paged, isFalse);
    expect(page.total, isNull);
    expect(page.pageRows, 87, reason: 'falls back to the list length');
  });

  test('a header that is empty or not a number reads as absent, not zero',
      () async {
    final page = await fetch(_ScriptedAdapter((_) => _list(
          [_row(1)],
          headers: {'X-Total-Count': '', 'X-Page-Rows': 'lots'},
        )));

    expect(page.total, isNull, reason: 'an empty count is not a count of 0');
    expect(page.paged, isFalse);
    expect(page.pageRows, 1);
  });

  test('header names are matched case-insensitively', () async {
    final page = await fetch(_ScriptedAdapter((_) => _list(
          [_row(1)],
          headers: {'x-total-count': '5', 'x-page-rows': '1'},
        )));

    expect(page.total, 5);
    expect(page.paged, isTrue);
  });

  test('sends limit and offset through', () async {
    final adapter = _ScriptedAdapter((_) => _list([]));
    await buildClient(adapter).getPaged<String>(
      '/api/account/history',
      (json) => json['show_id'].toString(),
      query: {'limit': 24, 'offset': 48},
    );

    expect(adapter.requests.single.uri.queryParameters,
        containsPair('limit', '24'));
    expect(adapter.requests.single.uri.queryParameters,
        containsPair('offset', '48'));
  });

  test('follows a redirect and reads the headers off the final hop', () async {
    // The proxy in front of an install redirects by design, and
    // the headers only exist on the response that actually carried the rows.
    final adapter = _ScriptedAdapter((options) {
      if (options.path.startsWith('https://streamio.example')) {
        return ResponseBody.fromString('', 302, headers: {
          'location': ['https://tunnel.example/api/account/watchlist'],
        });
      }
      return _list([_row(1)], headers: {'X-Page-Rows': '24'});
    });

    final page = await buildClient(adapter).getPaged<String>(
        '/api/account/watchlist', (json) => json['show_id'].toString());

    expect(page.paged, isTrue);
    expect(page.pageRows, 24);
  });
}
