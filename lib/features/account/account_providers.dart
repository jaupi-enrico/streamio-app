import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../state/api_providers.dart';

final watchlistProvider = FutureProvider.autoDispose<List<LibraryEntry>>((ref) async {
  return ref.watch(accountApiProvider).watchlist();
});

final favoritesProvider = FutureProvider.autoDispose<List<LibraryEntry>>((ref) async {
  return ref.watch(accountApiProvider).favorites();
});

final ratingsProvider = FutureProvider.autoDispose<List<RatingEntry>>((ref) async {
  return ref.watch(accountApiProvider).ratings();
});

final historyProvider = FutureProvider.autoDispose<List<HistoryEntry>>((ref) async {
  return ref.watch(accountApiProvider).history(limit: 100);
});

final preferencesProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(accountApiProvider).preferences();
});

/// Shares received, and the unread badge on the Social tab.
final shareInboxProvider = FutureProvider.autoDispose<List<Share>>((ref) async {
  return ref.watch(socialApiProvider).inbox();
});

final shareSentProvider = FutureProvider.autoDispose<List<Share>>((ref) async {
  return ref.watch(socialApiProvider).sent();
});

final unreadSharesProvider = FutureProvider.autoDispose<int>((ref) async {
  return ref.watch(socialApiProvider).unreadCount();
});

final followCountsProvider =
    FutureProvider.autoDispose<({int followers, int following})>((ref) async {
  return ref.watch(socialApiProvider).myFollowCounts();
});

/// Whether the signed-in account is on the server's `ADMIN_EMAILS` allowlist.
/// There's no endpoint for this — like the web account page, it's inferred by
/// probing an admin route and treating 403 as "not an admin".
final isAdminProvider = FutureProvider.autoDispose<bool>((ref) async {
  return ref.watch(settingsApiProvider).isAdmin();
});
