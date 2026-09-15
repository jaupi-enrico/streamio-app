import 'package:drift/drift.dart' show Value;

import '../api/account_api.dart';
import '../db/app_database.dart';

/// Pushes playback progress recorded during offline viewing up to the server.
///
/// Watching a download writes the position onto its own row with
/// `progressSynced = false`, because there's no network at the time by
/// definition. This drains those rows into `POST /api/account/history` the
/// next time the server is reachable, so an offline session shows up in
/// Continue Watching like any other.
class OfflineProgressSync {
  const OfflineProgressSync({required AppDatabase database, required AccountApi account})
      : _db = database,
        _account = account;

  final AppDatabase _db;
  final AccountApi _account;

  /// Returns how many entries were pushed. Failures are left unsynced for the
  /// next attempt rather than dropped.
  Future<int> flush() async {
    final rows = await _db.allDownloads();
    var pushed = 0;

    for (final row in rows) {
      if (row.progressSynced || row.progressSeconds <= 0) continue;

      try {
        await _account.saveProgress(
          provider: row.provider,
          showId: row.showId,
          episodeId: row.contentType == 'episode' ? row.contentId : null,
          episodeLabel: row.episodeLabel,
          progressSeconds: row.progressSeconds,
          durationSeconds: row.durationSeconds > 0 ? row.durationSeconds : null,
        );
        await _db.updateDownload(
            row.id, const DownloadsCompanion(progressSynced: Value(true)));
        pushed++;
      } catch (_) {
        // Still offline, or the session expired — try again next time.
        break;
      }
    }

    return pushed;
  }
}
