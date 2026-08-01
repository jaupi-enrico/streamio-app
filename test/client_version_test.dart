import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamio/core/api/api_client.dart';
import 'package:streamio/core/api/token_store.dart';
import 'package:streamio/core/app_version.dart';
import 'package:streamio/core/models/models.dart';
import 'package:streamio/shared/widgets/update_gate.dart';
import 'package:streamio/state/update_providers.dart';

/// In-memory keystore, same approach as api_client_test.dart.
class _MemoryStorage extends FlutterSecureStorage {
  _MemoryStorage([Map<String, String>? initial]) : _values = {...?initial};

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
  }) async {
    _values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      Map.of(_values);
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

/// Verbatim from the running server — `curl -H 'X-Client: app'
/// -H 'X-Client-Version: 1.0.0' /api/version` with an advisory policy set.
const _advisoryPayload = '''
{
  "server": {"version":"1.1.0","commit":"a3960d2","builtAt":"2026-08-01T12:58:01.539Z"},
  "api": {"version":1},
  "client": {
    "latest":"1.2.0","minSupported":"1.0.0",
    "downloadUrl":"https://github.com/streamio-org/streamio-website/releases",
    "notes":"Watch parties are faster and downloads resume properly.",
    "current":"1.0.0","updateAvailable":true,"updateRequired":false,"enforced":false
  }
}''';

/// The body the 426 gate returns (auth/clientVersion.ts).
const _blockedBody = '''
{
  "error":"Upgrade Required",
  "message":"This app version (1.0.0) is no longer supported. Please update to continue.",
  "client":{
    "current":"1.0.0","latest":"1.2.0","minSupported":"1.2.0",
    "downloadUrl":"https://example.com/app","notes":"Required security fix"
  }
}''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ApiClient buildClient(_ScriptedAdapter adapter, {Map<String, String>? tokens}) {
    final dio = Dio()..httpClientAdapter = adapter;
    return ApiClient(
      baseUrl: 'https://streamio.example',
      tokens: TokenStore(storage: _MemoryStorage(tokens)),
      dio: dio,
    );
  }

  group('X-Client-Version', () {
    tearDown(() => AppVersion.debugCurrent = null);

    test('is sent on every request when the version is known', () async {
      AppVersion.debugCurrent = '1.0.0';
      final adapter = _ScriptedAdapter((_) => _json('{"ok":true}', 200));

      await buildClient(adapter).get<Map<String, dynamic>>('/api/version');

      expect(adapter.requests.single.headers['X-Client-Version'], '1.0.0');
      expect(adapter.requests.single.headers['X-Client'], 'app');
    });

    test('is omitted rather than faked when the version is unknown', () async {
      AppVersion.debugCurrent = null;
      final adapter = _ScriptedAdapter((_) => _json('{"ok":true}', 200));

      await buildClient(adapter).get<Map<String, dynamic>>('/api/version');

      expect(adapter.requests.single.headers.containsKey('X-Client-Version'), isFalse);
    });
  });

  group('AppUpdateInfo', () {
    test('parses the advisory response the server actually sends', () {
      final info =
          AppUpdateInfo.fromJson(jsonDecode(_advisoryPayload) as Map<String, dynamic>);

      expect(info.serverVersion, '1.1.0');
      expect(info.latest, '1.2.0');
      expect(info.currentVersion, '1.0.0');
      expect(info.updateAvailable, isTrue);
      expect(info.updateRequired, isFalse);
      expect(info.enforced, isFalse);
      // Worth prompting, but not a dead end.
      expect(info.shouldPrompt, isTrue);
      expect(info.isBlocked, isFalse);
    });

    test('does not prompt when there is nowhere to send the user', () {
      const info = AppUpdateInfo(
        serverVersion: '1.1.0',
        serverCommit: 'abc',
        apiVersion: 1,
        latest: '1.2.0',
        minSupported: null,
        downloadUrl: null,
        notes: null,
        currentVersion: '1.0.0',
        updateAvailable: true,
        updateRequired: false,
        enforced: false,
      );
      expect(info.shouldPrompt, isFalse);
    });

    test('is only blocked when the server is actually enforcing', () {
      const advisoryOnly = AppUpdateInfo(
        serverVersion: '1.1.0',
        serverCommit: 'abc',
        apiVersion: 1,
        latest: '1.2.0',
        minSupported: '1.2.0',
        downloadUrl: 'https://example.com',
        notes: null,
        currentVersion: '1.0.0',
        updateAvailable: true,
        // Below the floor, but the floor isn't switched on.
        updateRequired: true,
        enforced: false,
      );
      expect(advisoryOnly.isBlocked, isFalse);
    });
  });

  group('426 handling', () {
    tearDown(() => AppVersion.debugCurrent = null);

    test('throws ClientOutdatedException carrying the download details', () async {
      final adapter = _ScriptedAdapter((_) => _json(_blockedBody, 426));
      final client = buildClient(adapter);

      await expectLater(
        client.get<Map<String, dynamic>>('/api/shows'),
        throwsA(isA<ClientOutdatedException>()
            .having((e) => e.latest, 'latest', '1.2.0')
            .having((e) => e.minSupported, 'minSupported', '1.2.0')
            .having((e) => e.downloadUrl, 'downloadUrl', 'https://example.com/app')
            .having((e) => e.message, 'message', contains('no longer supported'))),
      );
    });

    test('is broadcast app-wide, so any screen triggers the block', () async {
      final adapter = _ScriptedAdapter((_) => _json(_blockedBody, 426));
      final client = buildClient(adapter);

      final seen = expectLater(client.onClientOutdated.first, completes);
      await client.get<Map<String, dynamic>>('/api/shows').catchError((_) => <String, dynamic>{});
      await seen;
    });

    test('does not sign the user out — a new login would not help', () async {
      final adapter = _ScriptedAdapter((_) => _json(_blockedBody, 426));
      final client = buildClient(adapter, tokens: {
        'streamio.access_token': 'access-1',
        'streamio.refresh_token': 'refresh-1',
      });

      var authLost = false;
      client.onAuthLost.listen((_) => authLost = true);

      await client
          .get<Map<String, dynamic>>('/api/account/me', authenticated: true)
          .catchError((_) => <String, dynamic>{});
      await Future<void>.delayed(Duration.zero);

      expect(authLost, isFalse, reason: '426 is not an auth failure');
      expect(await client.tokens.accessToken, 'access-1',
          reason: 'tokens must survive — only a newer build fixes a 426');
      // Exactly one attempt: no refresh-and-replay, which would just 426 again.
      expect(adapter.requests, hasLength(1));
    });
  });

  group('UpdateGate', () {
    Widget wrap(List<Override> overrides) => ProviderScope(
          overrides: overrides,
          child: const MaterialApp(
            home: UpdateGate(child: Text('APP CONTENT')),
          ),
        );

    testWidgets('shows the app when no update is pending', (tester) async {
      await tester.pumpWidget(wrap([
        updateCheckProvider.overrideWith((ref) => null),
        clientOutdatedProvider.overrideWith((ref) => ClientOutdatedNotifier()),
      ]));
      await tester.pump();

      expect(find.text('APP CONTENT'), findsOneWidget);
      expect(find.text('Update required'), findsNothing);
    });

    testWidgets('offers an optional update once, without blocking', (tester) async {
      const info = AppUpdateInfo(
        serverVersion: '1.1.0',
        serverCommit: 'abc',
        apiVersion: 1,
        latest: '1.2.0',
        minSupported: '1.0.0',
        downloadUrl: 'https://example.com/app',
        notes: 'Watch parties are faster.',
        currentVersion: '1.0.0',
        updateAvailable: true,
        updateRequired: false,
        enforced: false,
      );

      await tester.pumpWidget(wrap([
        updateCheckProvider.overrideWith((ref) => info),
        clientOutdatedProvider.overrideWith((ref) => ClientOutdatedNotifier()),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('Streamio 1.2.0 is available.'), findsOneWidget);
      expect(find.text('Watch parties are faster.'), findsOneWidget);
      // Dismissible — the app underneath still works.
      expect(find.text('Later'), findsOneWidget);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('APP CONTENT'), findsOneWidget);
    });

    testWidgets('replaces the whole app when the server is blocking it', (tester) async {
      final notifier = ClientOutdatedNotifier()
        ..report(const ClientOutdatedException(
          message: 'This app version (1.0.0) is no longer supported.',
          latest: '1.2.0',
          minSupported: '1.2.0',
          downloadUrl: 'https://example.com/app',
        ));

      await tester.pumpWidget(wrap([
        updateCheckProvider.overrideWith((ref) => null),
        clientOutdatedProvider.overrideWith((ref) => notifier),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Update required'), findsOneWidget);
      expect(find.text('Download the new version'), findsOneWidget);
      // No way back into the app — every screen would only 426 again.
      expect(find.text('APP CONTENT'), findsNothing);
    });

    testWidgets('still explains itself when no download URL is configured',
        (tester) async {
      final notifier = ClientOutdatedNotifier()
        ..report(const ClientOutdatedException(
          message: 'This app version is no longer supported.',
        ));

      await tester.pumpWidget(wrap([
        updateCheckProvider.overrideWith((ref) => null),
        clientOutdatedProvider.overrideWith((ref) => notifier),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Update required'), findsOneWidget);
      expect(find.textContaining('Contact the server administrator'), findsOneWidget);
    });
  });
}
