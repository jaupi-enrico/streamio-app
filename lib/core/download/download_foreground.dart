import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The Android foreground service that keeps downloads alive in the
/// background — `DownloadService.kt`, driven over `streamio/downloads`.
///
/// The downloading itself stays in [DownloadManager]; the service only keeps
/// a process (and the Flutter engine `EngineHolder.kt` keeps in it) around
/// for that Dart code to run in once the app is hidden or swiped away.
///
/// Every call is a no-op off Android, and a failure is never thrown at the
/// caller: a notification that can't be shown must not fail a download.
class DownloadForeground {
  DownloadForeground({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('streamio/downloads');

  final MethodChannel _channel;

  bool get _supported => !kIsWeb && Platform.isAndroid;

  /// Called when the notification's "Pause all" is tapped, or Android's
  /// daily `dataSync` time limit runs out.
  void onPauseAll(Future<void> Function() handler) {
    if (!_supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pauseAll') await handler();
    });
  }

  /// Starts the service. False when Android refused (a foreground service
  /// can't be started while the app is in the background).
  Future<bool> start(DownloadProgress progress) async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('start', progress.toMap()) ?? false;
    } catch (err) {
      debugPrint('[downloads] could not start the foreground service: $err');
      return false;
    }
  }

  Future<void> update(DownloadProgress progress) =>
      _invoke('update', progress.toMap());

  Future<void> stop() => _invoke('stop');

  /// Android 13+ hides the progress notification without it. Asked once per
  /// download start; Android itself stops asking after a refusal.
  Future<void> requestNotificationPermission() =>
      _invoke('requestNotificationPermission');

  Future<void> _invoke(String method, [Object? arguments]) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } catch (err) {
      debugPrint('[downloads] $method failed: $err');
    }
  }
}

/// What the notification shows.
class DownloadProgress {
  const DownloadProgress({required this.count, this.title, this.progress});

  /// Downloads running right now.
  final int count;

  /// One of them, to name in the notification.
  final String? title;

  /// 0..1 across all of them, or null while it isn't known yet.
  final double? progress;

  Map<String, Object?> toMap() =>
      {'count': count, 'title': title, 'progress': progress};
}
