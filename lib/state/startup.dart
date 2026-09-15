import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/download/offline_sync.dart';
import 'api_providers.dart';
import 'auth_providers.dart';
import 'download_providers.dart';

/// One-time work after the app has a server and (maybe) a session:
///
///  * downloads left mid-flight by a kill are marked paused, so the UI offers
///    "resume" instead of showing a stuck spinner;
///  * progress recorded while offline is pushed to the server, and re-pushed
///    whenever connectivity comes back.
///
/// Watched by the root widget so it runs once per launch and again after a
/// server change (which rebuilds the API client this depends on).
final startupTasksProvider = Provider<StreamSubscription<dynamic>?>((ref) {
  final manager = ref.watch(downloadManagerProvider);
  unawaited(manager.reconcileOnStartup());

  Future<void> flushOfflineProgress() async {
    if (!ref.read(isSignedInProvider)) return;
    try {
      final sync = OfflineProgressSync(
        database: ref.read(appDatabaseProvider),
        account: ref.read(accountApiProvider),
      );
      await sync.flush();
    } catch (_) {
      // Best-effort by design: it retries on the next connectivity change.
    }
  }

  unawaited(flushOfflineProgress());

  final subscription = Connectivity().onConnectivityChanged.listen((results) {
    final online = results.any((result) => result != ConnectivityResult.none);
    if (online) unawaited(flushOfflineProgress());
  });
  ref.onDispose(subscription.cancel);

  return subscription;
});
