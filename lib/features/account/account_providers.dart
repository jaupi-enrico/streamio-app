import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/paged_response.dart';
import '../../core/models/models.dart';
import '../../state/api_providers.dart';

/// One account listing, accumulated a page at a time.
///
/// Same shape as `GenreBrowse` in `features/catalog/catalog_providers.dart`,
/// and for the same reasons: [loading] is the first page (blank the screen),
/// [loadingMore] is a later one (never blank what's already there).
class PagedList<T> {
  const PagedList({
    this.items = const [],
    this.total,
    this.loading = true,
    this.loadingMore = false,
    this.exhausted = false,
    this.error,
  });

  final List<T> items;

  /// The server's own count of the whole listing, or null if it didn't send
  /// one. Approximate by construction — see [PagedResponse.total] — so it is
  /// safe to display but never to page against.
  final int? total;

  final bool loading;
  final bool loadingMore;
  final bool exhausted;
  final Object? error;

  PagedList<T> copyWith({
    List<T>? items,
    int? total,
    bool? loading,
    bool? loadingMore,
    bool? exhausted,
    Object? error,
    bool clearError = false,
  }) {
    return PagedList<T>(
      items: items ?? this.items,
      total: total ?? this.total,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      exhausted: exhausted ?? this.exhausted,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// The paging half of an account listing, with the two rules that are easy to
/// get wrong written down once.
///
/// Subclasses supply only [fetchPage]. See `sendPage()` in
/// `../web/routes/account.router.ts` for the contract this implements.
abstract class PagedListNotifier<T> extends Notifier<PagedList<T>> {
  /// Matches `PAGE_SIZE` in `../web/public/scripts/account.js`. The server
  /// caps `limit` at 100 regardless.
  static const pageSize = 24;

  int _offset = 0;

  Future<PagedResponse<T>> fetchPage({required int limit, required int offset});

  /// The pre-paging way to fetch this listing, for a server that turns out not
  /// to page. Null when a single unpaged request is already the whole thing.
  ///
  /// Only history needs it: an old server *does* honour `limit`/`offset`
  /// there (it defaulted to 50 long before paging existed) but sends no
  /// headers, so [PagedResponse.paged] is false and the list would stop at one
  /// page of 24 — fewer rows than the app showed before this change. Watchlist
  /// and favorites need nothing: an old server ignores `limit` outright and
  /// has already sent everything.
  Future<List<T>>? fetchAllLegacy() => null;

  /// A server that didn't send `X-Page-Rows` doesn't page, so what arrived is
  /// the whole listing — asking again would return the same rows forever.
  bool _isExhausted(PagedResponse<T> page) =>
      !page.paged || page.pageRows < pageSize;

  @override
  PagedList<T> build() {
    // Riverpod keeps the notifier instance across a rebuild, so the offset has
    // to be reset by hand or the new first page is fetched from the old one's
    // position.
    _offset = 0;
    _loadFirst();
    return PagedList<T>();
  }

  Future<void> _loadFirst() async {
    try {
      final page = await fetchPage(limit: pageSize, offset: 0);
      if (!ref.mounted) return;

      // An unpaged server may have truncated us to one page — take the whole
      // listing the old way rather than silently showing less than the
      // previous release did.
      var items = page.items;
      if (!page.paged && items.length >= pageSize) {
        final all = await fetchAllLegacy();
        if (!ref.mounted) return;
        if (all != null) items = all;
      }

      _offset = page.pageRows;
      state = PagedList<T>(
        items: items,
        total: page.total,
        loading: false,
        exhausted: _isExhausted(page),
      );
    } catch (err) {
      if (!ref.mounted) return;
      state = PagedList<T>(loading: false, error: err);
    }
  }

  Future<void> refresh() {
    _offset = 0;
    state = PagedList<T>();
    return _loadFirst();
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || state.exhausted) return;

    state = state.copyWith(loadingMore: true);
    try {
      final page = await fetchPage(limit: pageSize, offset: _offset);
      if (!ref.mounted) return;

      // Advance by the rows the server *read*, not by the rows that arrived.
      // The 18+ gate drops entries after the query, so the list can be
      // shorter than the page — stepping by its length would re-request the
      // filtered rows and show the survivors twice.
      _offset += page.pageRows;
      state = state.copyWith(
        loadingMore: false,
        // A full page that came back half-empty still has more behind it, so
        // the end of the list is `pageRows`, never `items.length`.
        exhausted: _isExhausted(page),
        items: [...state.items, ...page.items],
        total: page.total ?? state.total,
      );
    } catch (_) {
      if (!ref.mounted) return;
      // Same rule as the catalog browse: a failed later page leaves what's on
      // screen alone, and the next scroll (or a Load more press) retries.
      state = state.copyWith(loadingMore: false);
    }
  }

  /// Drops a row that was just deleted server-side.
  ///
  /// Cheaper than a refresh and, more to the point, it keeps the user where
  /// they were — a reload would throw away every page they scrolled through.
  /// The offset moves down with it: the row is gone from the server's ordering
  /// too, so everything after it shifted up by one, and an unadjusted offset
  /// would step over a row on the next page.
  void removeWhere(bool Function(T entry) test) {
    final kept = state.items.where((entry) => !test(entry)).toList();
    if (kept.length == state.items.length) return;
    final removed = state.items.length - kept.length;
    _offset = (_offset - removed).clamp(0, _offset);
    state = state.copyWith(
      items: kept,
      total: state.total == null
          ? null
          : (state.total! - removed).clamp(0, state.total!),
    );
  }

  /// Empties the list without a round trip — for "clear history", where the
  /// server just deleted everything.
  void clear() {
    state = PagedList<T>(items: const [], total: 0, loading: false, exhausted: true);
  }
}

class _WatchlistNotifier extends PagedListNotifier<LibraryEntry> {
  @override
  Future<PagedResponse<LibraryEntry>> fetchPage({
    required int limit,
    required int offset,
  }) =>
      ref.read(accountApiProvider).watchlistPage(limit: limit, offset: offset);
}

class _FavoritesNotifier extends PagedListNotifier<LibraryEntry> {
  @override
  Future<PagedResponse<LibraryEntry>> fetchPage({
    required int limit,
    required int offset,
  }) =>
      ref.read(accountApiProvider).favoritesPage(limit: limit, offset: offset);
}

class _HistoryNotifier extends PagedListNotifier<HistoryEntry> {
  @override
  Future<PagedResponse<HistoryEntry>> fetchPage({
    required int limit,
    required int offset,
  }) =>
      ref.read(accountApiProvider).historyPage(limit: limit, offset: offset);

  @override
  Future<List<HistoryEntry>> fetchAllLegacy() =>
      ref.read(accountApiProvider).history(limit: 100);
}

final watchlistProvider = NotifierProvider.autoDispose<
    PagedListNotifier<LibraryEntry>,
    PagedList<LibraryEntry>>(_WatchlistNotifier.new);

final favoritesProvider = NotifierProvider.autoDispose<
    PagedListNotifier<LibraryEntry>,
    PagedList<LibraryEntry>>(_FavoritesNotifier.new);

/// Watch history. Used to ask for `limit: 100` in one shot and silently lose
/// everything past it; it now pages like the others.
final historyProvider = NotifierProvider.autoDispose<
    PagedListNotifier<HistoryEntry>, PagedList<HistoryEntry>>(
    _HistoryNotifier.new);

/// Ratings are deliberately unpaged — `/api/account/ratings` takes no
/// `limit`/`offset` and sends no paging headers, so there is nothing to page
/// against.
final ratingsProvider = FutureProvider.autoDispose<List<RatingEntry>>((ref) async {
  return ref.watch(accountApiProvider).ratings();
});

/// Your own statistics and every badge.
///
/// Not kept alive on purpose: the read is what awards badges server-side, so
/// re-entering the tab should re-ask rather than replay a cached answer.
final accountStatsProvider = FutureProvider.autoDispose<AccountStats>((ref) async {
  return ref.watch(accountApiProvider).stats();
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
