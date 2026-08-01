import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../shared/widgets/async_states.dart';
import '../../../state/api_providers.dart';
import '../../../state/show_summary_providers.dart';
import '../account_providers.dart';

enum LibraryKind { watchlist, favorites }

/// The watchlist and favorites tabs — same shape, different endpoint, so one
/// widget covers both.
class LibraryTab extends ConsumerWidget {
  const LibraryTab({super.key, required this.kind});

  final LibraryKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = kind == LibraryKind.watchlist
        ? ref.watch(watchlistProvider)
        : ref.watch(favoritesProvider);

    Future<void> refresh() async {
      if (kind == LibraryKind.watchlist) {
        ref.invalidate(watchlistProvider);
        await ref.read(watchlistProvider.future);
      } else {
        ref.invalidate(favoritesProvider);
        await ref.read(favoritesProvider.future);
      }
    }

    Future<void> remove(LibraryEntry entry) async {
      final api = ref.read(accountApiProvider);
      final ok = await runGuarded(
        context,
        () => kind == LibraryKind.watchlist
            ? api.removeFromWatchlist(entry.provider, entry.showId)
            : api.removeFavorite(entry.provider, entry.showId),
        successMessage: 'Removed',
      );
      if (ok) await refresh();
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: entriesAsync.when(
        loading: () => const LoadingState(),
        error: (error, _) => ErrorState(error: error, onRetry: refresh),
        data: (entries) {
          if (entries.isEmpty) {
            return EmptyState(
              message: kind == LibraryKind.watchlist
                  ? 'Your watchlist is empty. Add titles from their page.'
                  : 'No favorites yet.',
              icon: kind == LibraryKind.watchlist
                  ? Icons.bookmark_border
                  : Icons.favorite_border,
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final entry = entries[i];
              return _LibraryTile(
                entry: entry,
                onRemove: () => remove(entry),
              );
            },
          );
        },
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
