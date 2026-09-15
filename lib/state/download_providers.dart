import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/db/app_database.dart';
import '../core/download/download_manager.dart';
import '../core/download/local_media_server.dart';
import '../core/download/segment_store.dart';
import 'api_providers.dart';

/// One database and one segment store for the whole app. Both outlive any
/// screen — a download keeps running while the user browses elsewhere.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final segmentStoreProvider = Provider<SegmentStore>((ref) => SegmentStore());

final downloadManagerProvider = Provider<DownloadManager>((ref) {
  final manager = DownloadManager(
    database: ref.watch(appDatabaseProvider),
    store: ref.watch(segmentStoreProvider),
    client: ref.watch(apiClientProvider),
    content: ref.watch(contentApiProvider),
  );
  ref.onDispose(manager.dispose);
  return manager;
});

/// The loopback server used for offline playback. Started on demand by the
/// watch screen and stopped when playback ends.
final localMediaServerProvider = Provider<LocalMediaServer>((ref) {
  final server = LocalMediaServer(
    database: ref.watch(appDatabaseProvider),
    store: ref.watch(segmentStoreProvider),
  );
  ref.onDispose(server.stop);
  return server;
});

/// Every download, newest first — the Downloads screen's list.
final downloadsProvider = StreamProvider<List<DownloadRow>>((ref) {
  return ref.watch(appDatabaseProvider).watchAll();
});

/// The download for one piece of content, if any. Drives the
/// download/downloading/downloaded state of the button on details and watch.
final downloadForContentProvider = StreamProvider.autoDispose
    .family<DownloadRow?, ({String provider, String contentId})>((ref, args) {
  return ref
      .watch(appDatabaseProvider)
      .watchByContent(args.provider, args.contentId);
});

/// Total bytes the downloads directory occupies.
final downloadsSizeProvider = FutureProvider.autoDispose<int>((ref) async {
  // Recomputed whenever the download list changes, so deleting a title
  // updates the figure without a manual refresh.
  ref.watch(downloadsProvider);
  return ref.watch(segmentStoreProvider).totalSize();
});
