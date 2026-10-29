import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamio/core/api/api_client.dart';
import 'package:streamio/core/api/content_api.dart';
import 'package:streamio/core/api/token_store.dart';
import 'package:streamio/core/db/app_database.dart';
import 'package:streamio/core/download/download_foreground.dart';
import 'package:streamio/core/download/download_keep_alive.dart';
import 'package:streamio/core/download/download_manager.dart';
import 'package:streamio/core/download/hls_parser.dart';
import 'package:streamio/core/download/segment_store.dart';
import 'package:streamio/core/models/models.dart';

/// Background downloads: what a launch does with downloads a kill left
/// mid-flight, and the foreground service following what is running.

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

/// A server that can't be reached — the app launched offline.
class _UnreachableContent extends ContentApi {
  _UnreachableContent(super.client);

  @override
  Future<List<VideoServer>> servers(String contentId,
          {String? provider, String contentType = 'episode'}) =>
      Future.error(const ApiException('offline'));
}

/// Segment fetches that hang until released, so a download stays running.
class _HangingAdapter implements HttpClientAdapter {
  final release = Completer<void>();

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    await release.future;
    return ResponseBody.fromBytes(Uint8List(16), 200);
  }

  @override
  void close({bool force = false}) {}
}

class _RecordingForeground extends DownloadForeground {
  final calls = <String>[];
  Future<void> Function()? pauseAll;

  @override
  void onPauseAll(Future<void> Function() handler) => pauseAll = handler;

  @override
  Future<bool> start(DownloadProgress progress) async {
    calls.add('start:${progress.count}');
    return true;
  }

  @override
  Future<void> update(DownloadProgress progress) async => calls.add('update');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> requestNotificationPermission() async => calls.add('permission');
}

void main() {
  late AppDatabase db;
  late _HangingAdapter http;
  late DownloadManager manager;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    http = _HangingAdapter();
    final client = ApiClient(
      baseUrl: 'https://streamio.example',
      tokens: TokenStore(storage: _MemoryStorage()),
    );
    manager = DownloadManager(
      database: db,
      store: SegmentStore(storage: _MemoryStorage()),
      client: client,
      content: _UnreachableContent(client),
      httpClient: Dio()..httpClientAdapter = http,
    );
  });

  tearDown(() async {
    if (!http.release.isCompleted) http.release.complete();
    await db.close();
  });

  Future<void> insertDownload(String id, DownloadStatus status) =>
      db.upsertDownload(DownloadsCompanion.insert(
        id: id,
        provider: 'streamingcommunity',
        showId: 's',
        contentId: 'c-$id',
        title: 'Title $id',
        status: status,
        nonce: '00' * 16,
      ));

  Future<DownloadStatus?> statusOf(String id) async =>
      (await db.findDownload(id))?.status;

  /// A one-segment download, started for real: its fetch hangs, so it stays
  /// active until paused.
  Future<String> startHangingDownload() => manager.enqueue(
        provider: 'streamingcommunity',
        showId: 's',
        contentId: 'movie',
        contentType: 'movie',
        title: 'Matrix',
        plan: const DownloadPlan(
          source: PlaybackSource(
            url: '',
            inlineManifest: '#EXTM3U\n#EXTINF:4,\nhttps://cdn/seg0.ts\n#EXT-X-ENDLIST\n',
          ),
          master: null,
          options: [],
          headers: {},
        ),
        option: const DownloadOption(
          variant: HlsVariant(url: ''),
          audio: null,
          estimatedBytes: 0,
        ),
      );

  group('reconcileOnStartup', () {
    test('pauses what a kill left downloading and returns it to resume', () async {
      await insertDownload('killed', DownloadStatus.downloading);
      await insertDownload('user-paused', DownloadStatus.paused);

      expect(await manager.reconcileOnStartup(), ['killed']);
      expect(await statusOf('killed'), DownloadStatus.paused);
      expect(await statusOf('user-paused'), DownloadStatus.paused);
    });

    test('leaves a download this manager is running alone', () async {
      final id = await startHangingDownload();
      await pumpEventQueue();
      expect(manager.isActive(id), isTrue);

      expect(await manager.reconcileOnStartup(), isEmpty);
      expect(await statusOf(id), DownloadStatus.downloading);

      // Let it wind down before tearDown closes the database under it.
      manager.pause(id);
      http.release.complete();
      await pumpEventQueue();
      expect(manager.isActive(id), isFalse);
    });
  });

  group('resume', () {
    test('quiet: an unreachable server leaves the row paused', () async {
      await insertDownload('d', DownloadStatus.paused);
      await manager.resume('d', quiet: true);
      expect(await statusOf('d'), DownloadStatus.paused);
    });

    test('user-initiated: an unreachable server is reported as failed', () async {
      await insertDownload('d', DownloadStatus.paused);
      await manager.resume('d');
      expect(await statusOf('d'), DownloadStatus.failed);
    });
  });

  test('the foreground service follows the running downloads', () async {
    final foreground = _RecordingForeground();
    final keepAlive = DownloadKeepAlive(
      manager: manager,
      database: db,
      foreground: foreground,
    );

    final id = await startHangingDownload();
    await pumpEventQueue();
    expect(foreground.calls, ['permission', 'start:1']);

    // The notification's "Pause all".
    await foreground.pauseAll!();
    http.release.complete();
    await pumpEventQueue();

    expect(manager.isActive(id), isFalse);
    expect(await statusOf(id), DownloadStatus.paused);
    expect(foreground.calls.last, 'stop');

    await keepAlive.dispose();
  });
}
