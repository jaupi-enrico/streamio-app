import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../shared/widgets/async_states.dart';
import '../../../state/api_providers.dart';
import '../../../state/show_summary_providers.dart';
import '../account_providers.dart';

/// Watch history, with the same per-entry and clear-all deletes the web
/// account page has.
class HistoryTab extends ConsumerWidget {
  const HistoryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(historyProvider);

    Future<void> refresh() async {
      ref.invalidate(historyProvider);
      await ref.read(historyProvider.future);
    }

    Future<void> clearAll() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Clear watch history?'),
          content: const Text('This removes every entry. It can\'t be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Clear'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;

      final ok = await runGuarded(
        context,
        () => ref.read(accountApiProvider).clearHistory(),
        successMessage: 'History cleared',
      );
      if (ok) await refresh();
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: historyAsync.when(
        loading: () => const LoadingState(),
        error: (error, _) => ErrorState(error: error, onRetry: refresh),
        data: (entries) {
          if (entries.isEmpty) {
            return const EmptyState(
              message: 'Nothing watched yet.',
              icon: Icons.history,
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: entries.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              if (i == entries.length) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: OutlinedButton.icon(
                    onPressed: clearAll,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('Clear history'),
                  ),
                );
              }

              final entry = entries[i];
              return _HistoryTile(
                entry: entry,
                onRemove: () async {
                  final ok = await runGuarded(
                    context,
                    () => ref.read(accountApiProvider).deleteHistoryEntry(
                          entry.provider,
                          entry.showId,
                          episodeId: entry.episodeId,
                        ),
                    successMessage: 'Removed',
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

  static String _formatTime(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final rest = seconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:'
          '${rest.toString().padLeft(2, '0')}';
    }
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }
}

/// A history row carries only `(provider, show_id)`, so its title and poster
/// come from [showSummaryProvider] — see there for why.
class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({required this.entry, required this.onRemove});

  final HistoryEntry entry;
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
      onTap: () => _resume(context, entry, display.title),
      leading: SizedBox(
        width: 60,
        height: 40,
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
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              if (entry.episodeLabel != null) entry.episodeLabel!,
              if (entry.completed)
                'Watched'
              else
                'At ${HistoryTab._formatTime(entry.progressSeconds)}',
            ].join(' · '),
            style: Theme.of(context).textTheme.labelSmall,
          ),
          if (entry.progressFraction != null) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: entry.completed ? 1 : entry.progressFraction,
              minHeight: 2,
            ),
          ],
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Remove',
        onPressed: onRemove,
      ),
    );
  }

  void _resume(BuildContext context, HistoryEntry entry, String title) {
    final id = entry.episodeId ?? entry.showId;
    final query = {
      'contentType': entry.episodeId != null ? 'episode' : 'movie',
      'showId': entry.showId,
      'title': title,
      if (entry.episodeLabel != null) 'episodeLabel': entry.episodeLabel!,
      if (!entry.completed) 't': '${entry.progressSeconds}',
    };
    context.push(
        '/watch/${entry.provider}/${Uri.encodeComponent(id)}?${Uri(queryParameters: query).query}');
  }
}
