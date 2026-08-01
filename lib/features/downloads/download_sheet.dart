import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/download/download_manager.dart';
import '../../shared/widgets/async_states.dart';
import '../../state/download_providers.dart';

/// Quality picker for a download, opened from the details screen.
///
/// It resolves the stream first (same call the player makes) so the qualities
/// offered are the ones the master playlist actually has, then hands the
/// chosen one to [DownloadManager.enqueue].
class DownloadSheet extends ConsumerStatefulWidget {
  const DownloadSheet({
    super.key,
    required this.provider,
    required this.showId,
    required this.contentId,
    required this.contentType,
    required this.title,
    this.episodeLabel,
    this.poster,
  });

  final String provider;
  final String showId;
  final String contentId;
  final String contentType;
  final String title;
  final String? episodeLabel;
  final String? poster;

  @override
  ConsumerState<DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends ConsumerState<DownloadSheet> {
  DownloadPlan? _plan;
  Object? _error;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final plan = await ref.read(downloadManagerProvider).plan(
            provider: widget.provider,
            contentId: widget.contentId,
            contentType: widget.contentType,
          );
      if (mounted) setState(() => _plan = plan);
    } catch (err) {
      if (mounted) setState(() => _error = err);
    }
  }

  Future<void> _start(DownloadOption option) async {
    final plan = _plan;
    if (plan == null) return;

    setState(() => _starting = true);
    final ok = await runGuarded(
      context,
      () => ref.read(downloadManagerProvider).enqueue(
            provider: widget.provider,
            showId: widget.showId,
            contentId: widget.contentId,
            contentType: widget.contentType,
            title: widget.title,
            episodeLabel: widget.episodeLabel,
            poster: widget.poster,
            plan: plan,
            option: option,
          ),
      successMessage: 'Downloading ${widget.episodeLabel ?? widget.title}',
    );

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = ref
        .watch(downloadForContentProvider(
            (provider: widget.provider, contentId: widget.contentId)))
        .valueOrNull;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.download_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.episodeLabel != null
                        ? '${widget.title} · ${widget.episodeLabel}'
                        : widget.title,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Saved inside the app and encrypted — it plays offline here, '
              'and isn\'t readable as a file anywhere else on the device.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).hintColor),
            ),
            const SizedBox(height: 16),
            if (existing != null && existing.status == DownloadStatus.completed)
              const _AlreadyDownloaded()
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: ErrorState(
                    error: _error!, onRetry: _load, scrollable: false),
              )
            else if (_plan == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              ..._plan!.options.map(
                (option) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  enabled: !_starting,
                  leading: const Icon(Icons.high_quality_outlined),
                  title: Text(option.label),
                  subtitle: Text(option.audio != null
                      ? 'Video + separate audio track'
                      : 'Single stream'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _starting ? null : () => _start(option),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AlreadyDownloaded extends StatelessWidget {
  const _AlreadyDownloaded();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          const Expanded(child: Text('Already downloaded. Find it under Downloads.')),
        ],
      ),
    );
  }
}
