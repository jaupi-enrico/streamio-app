import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/content_api.dart';
import '../../core/models/models.dart';
import '../../state/api_providers.dart';
import '../../state/core_providers.dart';

/// The genre list for the active provider (`GET /api/genres`). Providers that
/// don't expose genres answer with an empty list, and the filter row simply
/// doesn't render.
final genresProvider = FutureProvider.autoDispose<List<Genre>>((ref) async {
  final api = ref.watch(contentApiProvider);
  return api.genres(provider: ref.watch(activeProviderNameProvider));
});

/// One genre's titles, accumulated page by page.
///
/// Separate from [genresProvider] because the two endpoints return different
/// things: `/api/genres` is the catalogue and its `Genre`s carry **no** shows,
/// while `/api/genres/:id` is the browse. Reading `shows` off a catalogue entry
/// always yields an empty list — which is what made picking a genre look like a
/// no-op.
class GenreBrowse {
  const GenreBrowse({
    this.name,
    this.shows = const [],
    this.loading = true,
    this.loadingMore = false,
    this.exhausted = false,
    this.error,
  });

  /// The genre's name as the *browse* reported it. Null until the first page
  /// lands — the screen falls back to the catalogue's name so the header isn't
  /// blank while loading, and an id that isn't in the catalogue at all (a
  /// details-page chip can carry one) still gets a title once this arrives.
  final String? name;
  final List<Show> shows;

  /// First page in flight. [loadingMore] is a later page, which must not blank
  /// what's already on screen.
  final bool loading;
  final bool loadingMore;

  /// A page came back empty, so there's nothing further to ask for.
  final bool exhausted;
  final Object? error;

  GenreBrowse copyWith({
    String? name,
    List<Show>? shows,
    bool? loading,
    bool? loadingMore,
    bool? exhausted,
    Object? error,
    bool clearError = false,
  }) {
    return GenreBrowse(
      name: name ?? this.name,
      shows: shows ?? this.shows,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      exhausted: exhausted ?? this.exhausted,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class GenreBrowseNotifier extends Notifier<GenreBrowse> {
  GenreBrowseNotifier(this._genreId);

  final String _genreId;

  late ContentApi _api;
  late String _provider;

  int _page = 1;

  @override
  GenreBrowse build() {
    // Riverpod keeps the notifier instance across rebuilds, so anything the
    // browse accumulated for the *previous* provider has to be re-read here.
    _api = ref.watch(contentApiProvider);
    _provider = ref.watch(activeProviderNameProvider);
    _page = 1;
    _loadFirst();
    return const GenreBrowse();
  }

  Future<void> _loadFirst() async {
    try {
      final genre = await _api.genre(_genreId, provider: _provider, page: 1);
      if (!ref.mounted) return;
      final shows = genre.shows;
      _page = 1;
      state = GenreBrowse(
        name: genre.name.isEmpty ? null : genre.name,
        shows: shows,
        loading: false,
        exhausted: shows.isEmpty,
      );
    } catch (err) {
      if (!ref.mounted) return;
      state = GenreBrowse(loading: false, error: err);
    }
  }

  Future<void> refresh() {
    state = const GenreBrowse();
    return _loadFirst();
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || state.exhausted) return;

    state = state.copyWith(loadingMore: true);
    try {
      final next = _page + 1;
      final genre = await _api.genre(_genreId, provider: _provider, page: next);
      if (!ref.mounted) return;

      _page = next;
      state = state.copyWith(
        loadingMore: false,
        exhausted: genre.shows.isEmpty,
        shows: [...state.shows, ...genre.shows],
      );
    } catch (_) {
      if (!ref.mounted) return;
      // Same rule as search: a failed "load more" leaves what's on screen
      // alone and the next scroll to the bottom retries.
      state = state.copyWith(loadingMore: false);
    }
  }
}

/// Keyed by genre id, and rebuilt when the provider changes — a genre id is the
/// upstream site's own, so it means nothing to a different source.
final genreBrowseProvider =
    NotifierProvider.autoDispose.family<GenreBrowseNotifier, GenreBrowse, String>(
        GenreBrowseNotifier.new);

/// Catalog body: the same `GET /api/home` payload the home screen uses, laid
/// out as grids instead of rails (that's exactly what `catalog.js` does).
final catalogCategoriesProvider =
    FutureProvider.autoDispose<List<Category>>((ref) async {
  final api = ref.watch(contentApiProvider);
  return api.home(provider: ref.watch(activeProviderNameProvider));
});

/// `catalog.js`'s `isFeaturedCategory()` — the row that becomes the top
/// carousel rather than a grid. Matched by name because the backend labels it
/// in Italian for some providers and English for others.
bool isFeaturedCategory(String name) {
  final lower = name.toLowerCase();
  return lower.contains('evidenza') ||
      lower.contains('featured') ||
      lower.contains('highlight') ||
      lower.contains('spotlight');
}
