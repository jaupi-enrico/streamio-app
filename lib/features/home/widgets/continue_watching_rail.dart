import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../state/show_summary_providers.dart';

/// `home.js`'s `#continueRow`: landscape cards with a progress bar, tapping
/// straight into playback at the stored position.
class ContinueWatchingRail extends StatelessWidget {
  const ContinueWatchingRail({
    super.key,
    required this.entries,
    required this.onResume,
    this.onDismiss,
  });

  final List<HistoryEntry> entries;
  /// The resolved title is passed along so the watch screen can show it
  /// while it loads — the history row itself has only the show id.
  final void Function(HistoryEntry entry, String title) onResume;
  final void Function(HistoryEntry entry)? onDismiss;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Continue watching',
                style: Theme.of(context).textTheme.headlineSmall),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _ContinueCard(
                entry: entries[i],
                onResume: onResume,
                onDismiss:
                    onDismiss == null ? null : () => onDismiss!(entries[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContinueCard extends ConsumerWidget {
  const _ContinueCard({required this.entry, required this.onResume, this.onDismiss});

  final HistoryEntry entry;
  final void Function(HistoryEntry entry, String title) onResume;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final progress = entry.progressFraction;
    // `watch_history` stores only `(provider, show_id)`; the title and poster
    // are hydrated per row — see [showSummaryProvider].
    final display = resolveShowDisplay(
      ref,
      provider: entry.provider,
      showId: entry.showId,
      title: entry.title,
      poster: entry.poster,
    );

    return SizedBox(
      width: 210,
      child: InkWell(
        onTap: () => onResume(entry, display.title),
        onLongPress: onDismiss,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (display.poster != null)
                      CachedNetworkImage(
                          imageUrl: display.poster!, fit: BoxFit.cover)
                    else
                      Container(color: const Color(0xFF1E2430)),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black87],
                        ),
                      ),
                    ),
                    const Center(
                      child: Icon(Icons.play_circle_fill,
                          size: 40, color: Colors.white70),
                    ),
                    if (progress != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          backgroundColor: Colors.white24,
                          valueColor:
                              AlwaysStoppedAnimation(theme.colorScheme.primary),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              display.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            if (entry.episodeLabel != null)
              Text(
                entry.episodeLabel!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
              ),
          ],
        ),
      ),
    );
  }
}
