import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../shared/widgets/async_states.dart';
import '../../state/api_providers.dart';

/// Sends a title (or a clip of it) to people you follow — `POST
/// /api/social/shares`, the app's equivalent of `openShareForCurrent()` in
/// `watch.js` and the share dialog on `details.html`.
class ShareSheet extends ConsumerStatefulWidget {
  const ShareSheet({
    super.key,
    required this.provider,
    required this.showId,
    required this.title,
    this.episodeId,
    this.episodeLabel,
    this.suggestedClipStart,
  });

  final String provider;
  final String showId;
  final String title;
  final String? episodeId;
  final String? episodeLabel;

  /// Current playback position when shared from the player, offered as the
  /// start of a clip.
  final int? suggestedClipStart;

  @override
  ConsumerState<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<ShareSheet> {
  final _search = TextEditingController();
  final _message = TextEditingController();
  final _selected = <String, UserSummary>{};

  Timer? _debounce;
  List<FollowSummary> _results = const [];
  bool _searching = false;
  bool _sending = false;
  bool _asClip = false;

  @override
  void initState() {
    super.initState();
    _asClip = widget.suggestedClipStart != null && widget.suggestedClipStart! > 0;
    _loadFollowing();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _message.dispose();
    super.dispose();
  }

  /// Opens on the people you already follow, so the common case needs no
  /// typing at all.
  Future<void> _loadFollowing() async {
    setState(() => _searching = true);
    try {
      final user = await ref.read(accountApiProvider).me();
      final following = await ref.read(socialApiProvider).following(user.id);
      if (mounted) {
        setState(() {
          _results = following;
          _searching = false;
        });
      }
    } catch (_) {
      // Falling back to an empty list is fine: the search field still works.
      if (mounted) setState(() => _searching = false);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      _loadFollowing();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search_(query));
  }

  Future<void> _search_(String query) async {
    setState(() => _searching = true);
    try {
      final results = await ref.read(socialApiProvider).searchUsers(query);
      if (mounted) {
        setState(() {
          _results = results;
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _send() async {
    if (_selected.isEmpty) {
      showToast(context, 'Pick at least one person.', isError: true);
      return;
    }

    setState(() => _sending = true);
    final ok = await runGuarded(
      context,
      () => ref.read(socialApiProvider).createShare(
            provider: widget.provider,
            showId: widget.showId,
            recipientIds: _selected.keys.toList(),
            episodeId: widget.episodeId,
            episodeLabel: widget.episodeLabel,
            clipStartSeconds: _asClip ? widget.suggestedClipStart : null,
            // A clip with only a start reads as "from here"; the backend
            // accepts a null end.
            clipEndSeconds: null,
            message: _message.text.trim(),
          ),
      successMessage: 'Shared with ${_selected.length} '
          '${_selected.length == 1 ? 'person' : 'people'}',
    );

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Share "${widget.title}"',
                  style: theme.textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              if (widget.episodeLabel != null)
                Text(widget.episodeLabel!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor)),
              const SizedBox(height: 12),
              TextField(
                controller: _search,
                onChanged: _onSearchChanged,
                decoration: const InputDecoration(
                  hintText: 'Search people',
                  prefixIcon: Icon(Icons.person_search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (_selected.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final user in _selected.values)
                      InputChip(
                        label: Text(user.label),
                        onDeleted: () => setState(() => _selected.remove(user.id)),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _results.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Nobody to show here yet.'),
                          )
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              for (final user in _results)
                                CheckboxListTile(
                                  dense: true,
                                  value: _selected.containsKey(user.id),
                                  onChanged: (checked) => setState(() {
                                    if (checked == true) {
                                      _selected[user.id] = user;
                                    } else {
                                      _selected.remove(user.id);
                                    }
                                  }),
                                  title: Text(user.label),
                                ),
                            ],
                          ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _message,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Add a message (optional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (widget.suggestedClipStart != null &&
                  widget.suggestedClipStart! > 0) ...[
                const SizedBox(height: 4),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _asClip,
                  onChanged: (value) => setState(() => _asClip = value ?? false),
                  title: Text(
                      'Start at ${_formatTime(widget.suggestedClipStart!)}'),
                ),
              ],
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                label: const Text('Share'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }
}
