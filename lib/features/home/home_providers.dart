import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../state/api_providers.dart';
import '../../state/auth_providers.dart';
import '../../state/core_providers.dart';

/// Home rails for the active provider (`GET /api/home`). The backend already
/// caches these in Redis per provider (`WebPlatformHandler.TTL`), so the app
/// doesn't add a second cache layer — it just refetches on provider switch
/// or pull-to-refresh.
final homeCategoriesProvider =
    FutureProvider.autoDispose<List<Category>>((ref) async {
  final api = ref.watch(contentApiProvider);
  final providerName = ref.watch(activeProviderNameProvider);
  return api.home(provider: providerName);
});

/// The "Continue Watching" rail — `home.js`'s `loadContinueWatching()`.
/// Signed-out users have no history, so it resolves empty rather than
/// erroring out and taking the whole screen down with it.
final continueWatchingProvider =
    FutureProvider.autoDispose<List<HistoryEntry>>((ref) async {
  if (!ref.watch(isSignedInProvider)) return const [];

  final entries = await ref.watch(accountApiProvider).history(limit: 20);
  // Finished titles have nothing left to continue.
  return entries.where((entry) => !entry.completed).toList();
});
