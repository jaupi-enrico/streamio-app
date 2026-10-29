import 'dart:async';

import '../db/app_database.dart';
import 'download_foreground.dart';
import 'download_manager.dart';

/// Keeps the Android foreground service ([DownloadForeground]) in step with
/// what [DownloadManager] is running: up the moment a download starts, its
/// notification fed aggregate progress, down once nothing is left.
///
/// Starting and stopping happen on the event that changes them; progress
/// updates in between are throttled to [_updateEvery] — the manager emits one
/// event per segment, far more often than a notification is worth redrawing.
class DownloadKeepAlive {
  DownloadKeepAlive({
    required DownloadManager manager,
    required AppDatabase database,
    DownloadForeground? foreground,
  })  : _manager = manager,
        _db = database,
        _foreground = foreground ?? DownloadForeground() {
    _foreground.onPauseAll(() async => _manager.pauseAll());
    _subscription = _manager.events.listen((_) => _onEvent());
  }

  static const _updateEvery = Duration(seconds: 1);

  /// Once per process: Android only shows the prompt a couple of times anyway.
  static bool _askedForNotifications = false;

  final DownloadManager _manager;
  final AppDatabase _db;
  final DownloadForeground _foreground;
  late final StreamSubscription<String> _subscription;

  Timer? _throttle;
  bool _running = false;

  /// Android refused to start the service (the app was already in the
  /// background). Not retried on every segment; cleared once idle.
  bool _refused = false;

  bool _syncing = false;
  bool _dirty = false;

  void _onEvent() {
    final wantRunning = _manager.activeIds.isNotEmpty;
    if (wantRunning != _running && !(wantRunning && _refused)) {
      _throttle?.cancel();
      _throttle = null;
      unawaited(_sync());
      return;
    }
    _throttle ??= Timer(_updateEvery, () {
      _throttle = null;
      unawaited(_sync());
    });
  }

  Future<void> _sync() async {
    if (_syncing) {
      _dirty = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _dirty = false;
        await _apply();
      } while (_dirty);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _apply() async {
    final ids = _manager.activeIds.toList();
    if (ids.isEmpty) {
      _refused = false;
      if (_running) {
        _running = false;
        await _foreground.stop();
      }
      return;
    }

    final progress = await _progressOf(ids);
    if (_running) {
      await _foreground.update(progress);
      return;
    }
    if (_refused) return;

    if (!_askedForNotifications) {
      _askedForNotifications = true;
      await _foreground.requestNotificationPermission();
    }
    _running = await _foreground.start(progress);
    _refused = !_running;
  }

  Future<DownloadProgress> _progressOf(List<String> ids) async {
    final rows = (await Future.wait(ids.map(_db.findDownload)))
        .whereType<DownloadRow>()
        .toList();

    var total = 0;
    var done = 0;
    for (final row in rows) {
      total += row.segmentsTotal;
      done += row.segmentsDone;
    }

    final first = rows.firstOrNull;
    final label = first?.episodeLabel;
    return DownloadProgress(
      count: ids.length,
      title: first == null ? null : (label == null ? first.title : '${first.title} · $label'),
      progress: total > 0 ? done / total : null,
    );
  }

  /// The manager this follows is going away (a server change disposes it,
  /// cancelling its downloads), so the service has nothing left to keep.
  Future<void> dispose() async {
    _throttle?.cancel();
    await _subscription.cancel();
    if (_running) {
      _running = false;
      await _foreground.stop();
    }
  }
}
