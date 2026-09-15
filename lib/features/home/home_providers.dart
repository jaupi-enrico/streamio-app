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
///
/// Deliberately **not** keyed on [activeProviderNameProvider]: what you have
/// half-watched is a property of you, not of the source you happen to be
/// browsing, and the rail keeps its contents across a source switch.
final continueWatchingProvider =
    FutureProvider.autoDispose<List<HistoryEntry>>((ref) async {
  if (!ref.watch(isSignedInProvider)) return const [];

  // Finished titles are dropped server-side: asking for the plain history and
  // filtering here means a run of recently-completed rows eats the whole limit
  // and the older in-progress ones never arrive.
  final entries = await ref
      .watch(accountApiProvider)
      .searchHistory(completed: false, limit: 100);

  // One card per title. Watching several episodes of a show leaves a row per
  // episode, and rows come back newest-first, so the first one is the one to
  // resume from.
  final seen = <String>{};
  return entries
      .where((entry) => seen.add('${entry.provider}:${entry.showId}'))
      .toList();
});
