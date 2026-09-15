import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../shared/widgets/async_states.dart';
import '../../../state/api_providers.dart';
import '../../../state/show_summary_providers.dart';
import '../account_providers.dart';

class RatingsTab extends ConsumerWidget {
  const RatingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratingsAsync = ref.watch(ratingsProvider);

    Future<void> refresh() async {
      ref.invalidate(ratingsProvider);
      await ref.read(ratingsProvider.future);
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: ratingsAsync.when(
        loading: () => const LoadingState(),
        error: (error, _) => ErrorState(error: error, onRetry: refresh),
        data: (ratings) {
          if (ratings.isEmpty) {
            return const EmptyState(
              message: 'You haven\'t rated anything yet.',
              icon: Icons.star_border,
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: ratings.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final rating = ratings[i];
              return _RatingTile(
                entry: rating,
                onRemove: () async {
                  final ok = await runGuarded(
                    context,
                    () => ref
                        .read(accountApiProvider)
                        .deleteRating(rating.provider, rating.showId),
                    successMessage: 'Rating removed',
                  );
                  if (ok) await refresh();
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// A `ratings` row is `(provider, show_id, rating)` and nothing else, so the
/// title and poster are hydrated through [showSummaryProvider].
class _RatingTile extends ConsumerWidget {
  const _RatingTile({required this.entry, required this.onRemove});

  final RatingEntry entry;
  final Future<void> Function() onRemove;

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
              : Container(color: const Color(0xFF1E2430)),
        ),
      ),
      title: Text(display.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          Icon(Icons.star,
              size: 14, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 4),
          Text('${entry.rating.round()}/10',
              style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Remove rating',
        onPressed: onRemove,
      ),
    );
  }
}
