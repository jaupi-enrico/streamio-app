import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../shared/widgets/async_states.dart';
import '../../../state/api_providers.dart';
import '../../../state/show_summary_providers.dart';
import '../account_providers.dart';
import '../widgets/paging.dart';

enum LibraryKind { watchlist, favorites }

/// The watchlist and favorites tabs — same shape, different endpoint, so one
/// widget covers both. Both page: the server sends 24 rows at a time and the
/// list grows on scroll or on **Load more**.
class LibraryTab extends ConsumerWidget {
  const LibraryTab({super.key, required this.kind});

  final LibraryKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider =
        kind == LibraryKind.watchlist ? watchlistProvider : favoritesProvider;
    final list = ref.watch(provider);
    final notifier = ref.read(provider.notifier);

    Future<void> refresh() => notifier.refresh();

    Future<void> remove(LibraryEntry entry) async {
      final api = ref.read(accountApiProvider);
      final ok = await runGuarded(
        context,
        () => kind == LibraryKind.watchlist
            ? api.removeFromWatchlist(entry.provider, entry.showId)
            : api.removeFavorite(entry.provider, entry.showId),
        successMessage: 'Removed',
      );
      // Drop the row in place rather than reloading — a refresh would throw
      // away every page the user has scrolled through to get here.
      if (ok) {
        notifier.removeWhere((e) =>
            e.provider == entry.provider && e.showId == entry.showId);
      }
    }

    if (list.loading) return const LoadingState();
    if (list.error != null && list.items.isEmpty) {
      return ErrorState(error: list.error!, onRetry: refresh);
    }

    if (list.items.isEmpty) {
      return RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.5,
              child: EmptyState(
                message: kind == LibraryKind.watchlist
                    ? 'Your watchlist is empty. Add titles from their page.'
                    : 'No favorites yet.',
                icon: kind == LibraryKind.watchlist
                    ? Icons.bookmark_border
                    : Icons.favorite_border,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: PagedScrollLoader(
        onLoadMore: notifier.loadMore,
        child: ListView.separated(
          padding: const EdgeInsets.only(bottom: 8),
          // Header line, the rows, then the footer — which stays in the list
          // even once exhausted, so it can hand focus on instead of vanishing
          // out from under a remote.
          itemCount: list.items.length + 2,
          // No rule under the header line, and none above the footer once it
          // has collapsed to nothing — that would leave a stray line hanging
          // below the last row.
          separatorBuilder: (_, index) =>
              index == 0 || index == list.items.length
                  ? const SizedBox.shrink()
                  : const Divider(height: 1),
          itemBuilder: (context, i) {
            if (i == 0) {
              return PagedListCount(
                list: list,
                noun: kind == LibraryKind.watchlist ? 'title' : 'favorite',
              );
            }
            final index = i - 1;
            if (index == list.items.length) {
              return PagedListFooter(list: list, onLoadMore: notifier.loadMore);
            }
            final entry = list.items[index];
            return _LibraryTile(entry: entry, onRemove: () => remove(entry));
          },
        ),
      ),
    );
  }
}

/// The row only stores `(provider, show_id)`, so the title and poster are
/// looked up through [showSummaryProvider] — see there for why.
class _LibraryTile extends ConsumerWidget {
  const _LibraryTile({required this.entry, required this.onRemove});

  final LibraryEntry entry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final display = resolveShowDisplay(
      ref,
      provider: entry.provider,
      showId: entry.showId,
      title: entry.title,
      poster: entry.poster,
    );

    return ListTile(
      onTap: () => context.push(
          '/details/${entry.provider}/${Uri.encodeComponent(entry.showId)}'),
      leading: SizedBox(
        width: 44,
        height: 64,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: display.poster != null
              ? CachedNetworkImage(
                  imageUrl: display.poster!,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) =>
                      Container(color: const Color(0xFF1E2430)),
                )
              : Container(
                  color: const Color(0xFF1E2430),
                  child: const Icon(Icons.movie_outlined,
                      color: Colors.white24, size: 18),
                ),
        ),
      ),
      title: Text(display.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(entry.provider,
          style: Theme.of(context).textTheme.labelSmall),
      trailing: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Remove',
        onPressed: onRemove,
      ),
    );
  }
}
