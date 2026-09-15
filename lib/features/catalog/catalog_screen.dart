import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../shared/widgets/async_states.dart';
import '../../shared/widgets/poster_card.dart';
import '../../shared/widgets/provider_picker.dart';
import '../../shared/widgets/tv_focusable.dart';
import '../../state/core_providers.dart';
import 'catalog_providers.dart';

/// `catalog.html` / `catalog.js`: a featured carousel plus one grid per
/// category, with a genre filter row on top.
class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key, this.initialGenreId});

  final String? initialGenreId;

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  final _scrollController = ScrollController();

  String? _genreId;

  @override
  void initState() {
    super.initState();
    _genreId = widget.initialGenreId;
    _scrollController.addListener(_onScroll);
  }

  /// Arriving from a genre chip elsewhere in the app re-uses this State (the
  /// shell keeps one page per tab), so the new genre only reaches us as a
  /// widget update.
  @override
  void didUpdateWidget(CatalogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialGenreId != oldWidget.initialGenreId &&
        widget.initialGenreId != null) {
      setState(() => _genreId = widget.initialGenreId);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Same trigger as the search screen's: within 400px of the bottom asks for
  /// the next page. No-op unless a genre is selected — the category body isn't
  /// paged.
  void _onScroll() {
    final genreId = _genreId;
    if (genreId == null || !_scrollController.hasClients) return;

    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      ref.read(genreBrowseProvider(genreId).notifier).loadMore();
    }
  }

  void _selectGenre(String? id) {
    setState(() => _genreId = id);
    // The list length changes out from under the controller; without this a
    // switch from a long genre to a short one can leave it scrolled past the
    // new extent, which fires _onScroll immediately.
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  /// The active provider, not `show.providerName` — see the note on
  /// `HomeScreen._openDetails`.
  void _open(BuildContext context, Show show, String activeProvider) {
    context.push('/details/$activeProvider/${Uri.encodeComponent(show.id)}');
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(catalogCategoriesProvider);
    final genresAsync = ref.watch(genresProvider);
    final activeProvider = ref.watch(activeProviderNameProvider);
    final genreId = _genreId;

    Future<void> refresh() async {
      ref.invalidate(catalogCategoriesProvider);
      ref.invalidate(genresProvider);
      if (genreId != null) {
        await ref.read(genreBrowseProvider(genreId).notifier).refresh();
      }
      await ref.read(catalogCategoriesProvider.future);
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: refresh,
          child: categoriesAsync.when(
            loading: () => const LoadingState(),
            error: (error, _) => ErrorState(error: error, onRetry: refresh),
            data: (categories) {
              if (categories.isEmpty) {
                return const EmptyState(
                    message: 'No categories available for this provider.');
              }

              final featured = categories
                  .where((c) => isFeaturedCategory(c.name))
                  .expand((c) => c.list.whereType<Show>())
                  .toList();
              final regular =
                  categories.where((c) => !isFeaturedCategory(c.name)).toList();

              return CustomScrollView(
                controller: _scrollController,
                slivers: [
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),
                  const SliverToBoxAdapter(child: ProviderPicker()),
                  SliverToBoxAdapter(
                    child: genresAsync.maybeWhen(
                      data: (genres) => _GenreFilter(
                        genres: genres,
                        selectedId: genreId,
                        onSelected: _selectGenre,
                      ),
                      orElse: () => const SizedBox.shrink(),
                    ),
                  ),

                  // A picked genre replaces the whole catalog body with that
                  // genre's own titles, which are a request of their own —
                  // the catalogue entry carries only an id and a name.
                  if (genreId != null)
                    ..._genreSlivers(
                      genreId,
                      // The catalogue's name shows immediately; the browse's
                      // own replaces it, and covers an id that isn't in the
                      // catalogue (a details-page chip can carry one).
                      catalogueName: genresAsync.value
                          ?.where((genre) => genre.id == genreId)
                          .firstOrNull
                          ?.name,
                      activeProvider: activeProvider,
                    )
                  else ...[
                    if (featured.isNotEmpty) ...[
                      const SliverToBoxAdapter(
                          child: _SectionHeader(title: 'Featured')),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 190,
                          child: FocusTraversalGroup(
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: featured.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, i) => _FeaturedCard(
                                show: featured[i],
                                onTap: () =>
                                    _open(context, featured[i], activeProvider),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    for (final category in regular) ...[
                      if (category.list.whereType<Show>().isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: _SectionHeader(
                            title: category.name,
                            count: category.list.whereType<Show>().length,
                          ),
                        ),
                        _ShowGrid(
                          shows: category.list.whereType<Show>().toList(),
                          onTap: (show) => _open(context, show, activeProvider),
                        ),
                      ],
                    ],
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// The selected genre's body: header, then its titles, then whatever the
  /// paging is doing. Errors are shown in place rather than replacing the
  /// screen, so the filter row stays reachable and another genre can be picked
  /// — which matters for the two the backend refuses outright (400 for a
  /// provider with no genre filter, 403 for an 18+ genre behind a closed gate).
  List<Widget> _genreSlivers(
    String genreId, {
    required String? catalogueName,
    required String activeProvider,
  }) {
    final browse = ref.watch(genreBrowseProvider(genreId));
    final title = browse.name ?? catalogueName ?? 'Genre';

    if (browse.loading) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: LoadingState(),
          ),
        ),
      ];
    }

    if (browse.error != null) {
      return [
        SliverToBoxAdapter(
          child: ErrorState(
            error: browse.error!,
            scrollable: false,
            onRetry: () =>
                ref.read(genreBrowseProvider(genreId).notifier).refresh(),
          ),
        ),
      ];
    }

    return [
      SliverToBoxAdapter(
        child: _SectionHeader(title: title, count: browse.shows.length),
      ),
      if (browse.shows.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Nothing listed under this genre.'),
          ),
        )
      else
        _ShowGrid(
          shows: browse.shows,
          onTap: (show) => _open(context, show, activeProvider),
        ),
      if (browse.loadingMore)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: LoadingState(),
          ),
        ),
    ];
  }
}

class _GenreFilter extends StatelessWidget {
  const _GenreFilter({
    required this.genres,
    required this.selectedId,
    required this.onSelected,
  });

  final List<Genre> genres;
  final String? selectedId;
  final void Function(String? id) onSelected;

  @override
  Widget build(BuildContext context) {
    if (genres.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        height: 40,
        child: FocusTraversalGroup(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: genres.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              if (i == 0) {
                return ChoiceChip(
                  label: const Text('All'),
                  selected: selectedId == null,
                  onSelected: (_) => onSelected(null),
                );
              }
              final genre = genres[i - 1];
              return ChoiceChip(
                label: Text(genre.name),
                selected: genre.id == selectedId,
                onSelected: (selected) =>
                    onSelected(selected ? genre.id : null),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.count});

  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: theme.textTheme.headlineSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          if (count != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$count', style: theme.textTheme.labelSmall),
            ),
        ],
      ),
    );
  }
}

class _ShowGrid extends StatelessWidget {
  const _ShowGrid({required this.shows, required this.onTap});

  final List<Show> shows;
  final void Function(Show show) onTap;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 140,
          childAspectRatio: 0.55,
          crossAxisSpacing: 10,
          mainAxisSpacing: 14,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) => PosterCard(
              show: shows[i], width: 140, onTap: () => onTap(shows[i])),
          childCount: shows.length,
        ),
      ),
    );
  }
}

/// `catalog.js`'s `renderFeatCard()`: banner-first landscape card that falls
/// back to the poster when there's no banner.
class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.show, required this.onTap});

  final Show show;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final banner = switch (show) {
      Movie(:final banner) => banner,
      TvShow(:final banner) => banner,
      _ => null,
    };
    final image = banner ?? show.poster;

    return SizedBox(
      width: 260,
      child: TvFocusable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: image != null
                    ? CachedNetworkImage(
                        imageUrl: image,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorWidget: (_, __, ___) =>
                            Container(color: const Color(0xFF1E2430)),
                      )
                    : Container(color: const Color(0xFF1E2430)),
              ),
            ),
            const SizedBox(height: 6),
            Text(show.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
