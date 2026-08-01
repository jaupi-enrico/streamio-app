import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../shared/widgets/async_states.dart';
import '../../../state/api_providers.dart';
import '../account_providers.dart';

/// The social tab: shares received and sent, plus finding and following
/// people. Mirrors `panel-social` in `account.html` and `social.js`.
class SocialTab extends ConsumerStatefulWidget {
  const SocialTab({super.key});

  @override
  ConsumerState<SocialTab> createState() => _SocialTabState();
}

class _SocialTabState extends ConsumerState<SocialTab>
    with SingleTickerProviderStateMixin {
  late final TabController _controller =
      TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadSharesProvider).valueOrNull ?? 0;

    return Column(
      children: [
        TabBar(
          controller: _controller,
          tabs: [
            Tab(text: unread > 0 ? 'Inbox ($unread)' : 'Inbox'),
            const Tab(text: 'Sent'),
            const Tab(text: 'People'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _controller,
            children: const [
              _SharesList(incoming: true),
              _SharesList(incoming: false),
              _PeopleTab(),
            ],
          ),
        ),
      ],
    );
  }
}

class _SharesList extends ConsumerWidget {
  const _SharesList({required this.incoming});

  final bool incoming;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sharesAsync =
        incoming ? ref.watch(shareInboxProvider) : ref.watch(shareSentProvider);

    Future<void> refresh() async {
      if (incoming) {
        ref
          ..invalidate(shareInboxProvider)
          ..invalidate(unreadSharesProvider);
        await ref.read(shareInboxProvider.future);
      } else {
        ref.invalidate(shareSentProvider);
        await ref.read(shareSentProvider.future);
      }
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: sharesAsync.when(
        loading: () => const LoadingState(),
        error: (error, _) => ErrorState(error: error, onRetry: refresh),
        data: (shares) {
          if (shares.isEmpty) {
            return EmptyState(
              message: incoming
                  ? 'Nothing shared with you yet.'
                  : 'You haven\'t shared anything yet.',
              icon: Icons.inbox_outlined,
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: shares.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) => _ShareTile(
              share: shares[i],
              incoming: incoming,
              onChanged: refresh,
            ),
          );
        },
      ),
    );
  }
}

class _ShareTile extends ConsumerWidget {
  const _ShareTile({
    required this.share,
    required this.incoming,
    required this.onChanged,
  });

  final Share share;
  final bool incoming;
  final Future<void> Function() onChanged;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    if (incoming && share.isUnread) {
      // Best-effort: opening it is what "read" means, and a failed mark
      // shouldn't block navigation.
      unawaited(ref
          .read(socialApiProvider)
          .markShareRead(share.id)
          .then((_) => ref.invalidate(unreadSharesProvider))
          .catchError((_) {}));
    }

    final playbackId = share.episodeId ?? share.showId;
    final query = {
      'contentType': share.episodeId != null ? 'episode' : 'movie',
      'showId': share.showId,
      if (share.episodeLabel != null) 'episodeLabel': share.episodeLabel!,
      if (share.clipStartSeconds != null) 't': '${share.clipStartSeconds}',
    };
    if (context.mounted) {
      context.push(
          '/watch/${share.provider}/${Uri.encodeComponent(playbackId)}?${Uri(queryParameters: query).query}');
    }
  }

  Future<void> _react(BuildContext context, WidgetRef ref) async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            children: [
              for (final emoji in kAllowedReactions)
                InkWell(
                  onTap: () => Navigator.of(context).pop(emoji),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(emoji, style: const TextStyle(fontSize: 28)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (emoji == null || !context.mounted) return;
    final ok = await runGuarded(
      context,
      () => ref.read(socialApiProvider).react(share.id, emoji),
    );
    if (ok) await onChanged();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final who = incoming
        ? share.sender.label
        : share.recipients.map((r) => r.label).join(', ');

    return ListTile(
      onTap: () => _open(context, ref),
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.surface,
        child: Text(incoming ? share.sender.initial : '→'),
      ),
      title: Text(
        share.episodeLabel != null
            ? '${share.showId} · ${share.episodeLabel}'
            : share.showId,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              incoming ? 'From $who' : 'To ${who.isEmpty ? 'nobody' : who}',
              if (share.isClip) 'clip',
            ].join(' · '),
            style: theme.textTheme.labelSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (share.message != null && share.message!.isNotEmpty)
            Text(share.message!, maxLines: 2, overflow: TextOverflow.ellipsis),
          if (share.reactions.isNotEmpty)
            Text(share.reactions.map((r) => r.emoji).join(' ')),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (incoming && share.isUnread)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.add_reaction_outlined),
            tooltip: 'React',
            onPressed: () => _react(context, ref),
          ),
          if (!incoming)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Delete',
              onPressed: () async {
                final ok = await runGuarded(
                  context,
                  () => ref.read(socialApiProvider).deleteShare(share.id),
                  successMessage: 'Share deleted',
                );
                if (ok) await onChanged();
              },
            ),
        ],
      ),
    );
  }
}

class _PeopleTab extends ConsumerStatefulWidget {
  const _PeopleTab();

  @override
  ConsumerState<_PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends ConsumerState<_PeopleTab> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<FollowSummary> _results = const [];
  bool _loading = false;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _loadFollowing();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadFollowing() async {
    setState(() => _loading = true);
    try {
      final user = await ref.read(accountApiProvider).me();
      final following = await ref.read(socialApiProvider).following(user.id);
      if (mounted) {
        setState(() {
          _results = following;
          _loading = false;
          _searched = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      _loadFollowing();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(query));
  }

  Future<void> _run(String query) async {
    setState(() => _loading = true);
    try {
      final results = await ref.read(socialApiProvider).searchUsers(query);
      if (mounted) {
        setState(() {
          _results = results;
          _loading = false;
          _searched = true;
        });
      }
    } catch (err) {
      if (mounted) {
        setState(() => _loading = false);
        showToast(context, ErrorState.messageFor(err), isError: true);
      }
    }
  }

  Future<void> _toggleFollow(FollowSummary user) async {
    final api = ref.read(socialApiProvider);
    final ok = await runGuarded(
      context,
      () => user.isFollowing ? api.unfollow(user.id) : api.follow(user.id),
      successMessage: user.isFollowing
          ? 'Unfollowed ${user.label}'
          : 'Following ${user.label}',
    );
    if (!ok) return;

    ref.invalidate(followCountsProvider);
    if (_searched) {
      await _run(_search.text.trim());
    } else {
      await _loadFollowing();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _search,
            onChanged: _onChanged,
            decoration: const InputDecoration(
              hintText: 'Find people by name or email',
              prefixIcon: Icon(Icons.person_search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const LoadingState()
              : _results.isEmpty
                  ? EmptyState(
                      message: _searched
                          ? 'Nobody matched that search.'
                          : 'You\'re not following anyone yet.',
                      icon: Icons.people_outline,
                    )
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final user = _results[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                Theme.of(context).colorScheme.surface,
                            child: Text(user.initial),
                          ),
                          title: Text(user.label),
                          trailing: TextButton(
                            onPressed: () => _toggleFollow(user),
                            child:
                                Text(user.isFollowing ? 'Unfollow' : 'Follow'),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
