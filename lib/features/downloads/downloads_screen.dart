import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/app_database.dart';
import '../../shared/widgets/async_states.dart';
import '../../state/download_providers.dart';

/// The offline library: what's downloading now, and what's ready to watch
/// with no network at all.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
  }

  static String formatDuration(int seconds) {
    if (seconds <= 0) return '';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  void _play(BuildContext context, DownloadRow row) {
    final query = {
      'contentType': row.contentType,
      'showId': row.showId,
      'title': row.title,
      if (row.episodeLabel != null) 'episodeLabel': row.episodeLabel!,
      'download': row.id,
      if (row.progressSeconds > 0) 't': '${row.progressSeconds}',
    };
    context.push(
        '/watch/${row.provider}/${Uri.encodeComponent(row.contentId)}?${Uri(queryParameters: query).query}');
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, DownloadRow row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete download?'),
        content: Text(
            'This removes the downloaded copy of "${row.episodeLabel ?? row.title}" from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    await runGuarded(
      context,
      () => ref.read(downloadManagerProvider).remove(row.id),
      successMessage: 'Download deleted',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadsAsync = ref.watch(downloadsProvider);
    final sizeAsync = ref.watch(downloadsSizeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                sizeAsync.maybeWhen(
                  data: (bytes) => '${formatBytes(bytes)} used on this device',
                  orElse: () => '',
                ),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
        ),
      ),
      body: downloadsAsync.when(
        loading: () => const LoadingState(),
        error: (error, _) => ErrorState(error: error),
        data: (rows) {
          if (rows.isEmpty) {
            return const EmptyState(
              message:
                  'Nothing downloaded yet.\nUse the download button on a movie or episode '
                  'to keep it for offline viewing.',
              icon: Icons.download_outlined,
            );
          }

          final active = rows
              .where((row) => row.status != DownloadStatus.completed)
              .toList();
          final completed = rows
              .where((row) => row.status == DownloadStatus.completed)
              .toList();

          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (active.isNotEmpty) ...[
                const _SectionTitle('In progress'),
                for (final row in active)
                  _DownloadTile(
                    row: row,
                    onPlay: null,
                    onDelete: () => _confirmDelete(context, ref, row),
                  ),
              ],
              if (completed.isNotEmpty) ...[
                const _SectionTitle('Ready to watch offline'),
                for (final row in completed)
                  _DownloadTile(
                    row: row,
                    onPlay: () => _play(context, row),
                    onDelete: () => _confirmDelete(context, ref, row),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _DownloadTile extends ConsumerWidget {
  const _DownloadTile({
    required this.row,
    required this.onPlay,
    required this.onDelete,
  });

  final DownloadRow row;
  final VoidCallback? onPlay;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final manager = ref.watch(downloadManagerProvider);

    final fraction = row.segmentsTotal > 0
        ? (row.segmentsDone / row.segmentsTotal).clamp(0.0, 1.0)
        : 0.0;

    final subtitle = switch (row.status) {
      DownloadStatus.completed => [
          if (row.quality != null) row.quality!,
          if (row.durationSeconds > 0)
            DownloadsScreen.formatDuration(row.durationSeconds),
          DownloadsScreen.formatBytes(row.bytesDownloaded),
        ].where((part) => part.isNotEmpty).join(' · '),
      DownloadStatus.failed => row.errorMessage ?? 'Download failed',
      DownloadStatus.paused => 'Paused · ${(fraction * 100).round()}%',
      DownloadStatus.queued => 'Queued',
      DownloadStatus.downloading =>
        '${(fraction * 100).round()}% · ${DownloadsScreen.formatBytes(row.bytesDownloaded)}',
    };

    return ListTile(
      onTap: onPlay,
      leading: SizedBox(
        width: 54,
        height: 78,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: row.poster != null
              ? CachedNetworkImage(
                  imageUrl: row.poster!,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) =>
                      Container(color: const Color(0xFF1E2430)),
                )
              : Container(
                  color: const Color(0xFF1E2430),
                  child: const Icon(Icons.movie_outlined, color: Colors.white24),
                ),
        ),
      ),
      title: Text(
        row.episodeLabel != null ? '${row.title} · ${row.episodeLabel}' : row.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(subtitle,
              style: theme.textTheme.labelSmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          if (row.status == DownloadStatus.downloading ||
              row.status == DownloadStatus.paused) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(value: fraction, minHeight: 3),
          ],
        ],
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (action) {
          switch (action) {
            case 'pause':
              manager.pause(row.id);
            case 'resume':
              manager.resume(row.id);
            case 'delete':
              onDelete();
          }
        },
        itemBuilder: (context) => [
          if (row.status == DownloadStatus.downloading)
            const PopupMenuItem(value: 'pause', child: Text('Pause')),
          if (row.status == DownloadStatus.paused ||
              row.status == DownloadStatus.failed ||
              row.status == DownloadStatus.queued)
            const PopupMenuItem(value: 'resume', child: Text('Resume')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}
