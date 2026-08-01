import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../shared/widgets/async_states.dart';
import '../../state/auth_providers.dart';
import '../../state/server_config_provider.dart';
import 'account_providers.dart';
import 'tabs/history_tab.dart';
import 'tabs/library_tab.dart';
import 'tabs/preferences_tab.dart';
import 'tabs/profile_tab.dart';
import 'tabs/ratings_tab.dart';
import 'tabs/social_tab.dart';

/// `account.html` — the same seven tabs (watchlist, favorites, history,
/// profile, preferences, social, admin), with the admin one shown only to
/// accounts the server considers admins.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key, this.initialTab});

  final String? initialTab;

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen>
    with SingleTickerProviderStateMixin {
  static const _tabs = <({String id, String label, IconData icon})>[
    (id: 'watchlist', label: 'Watchlist', icon: Icons.bookmark_border),
    (id: 'favorites', label: 'Favorites', icon: Icons.favorite_border),
    (id: 'history', label: 'History', icon: Icons.history),
    (id: 'ratings', label: 'Ratings', icon: Icons.star_border),
    (id: 'social', label: 'Social', icon: Icons.people_outline),
    (id: 'preferences', label: 'Settings', icon: Icons.tune),
    (id: 'profile', label: 'Profile', icon: Icons.person_outline),
  ];

  /// Vertical room the hero row needs. `expandedHeight` has to be stated up
  /// front, so the toolbar and the tab bar are added on top of this rather
  /// than sharing it — otherwise the hero lays out behind both.
  static const _heroHeight = 104.0;

  late final TabController _controller = TabController(
    length: _tabs.length,
    vsync: this,
    initialIndex: _initialIndex,
  );

  int get _initialIndex {
    final index = _tabs.indexWhere((tab) => tab.id == widget.initialTab);
    return index >= 0 ? index : 0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final isAdmin = ref.watch(isAdminProvider).valueOrNull ?? false;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Account')),
        body: EmptyState(
          message: 'Sign in to see your watchlist, history and social feed.',
          icon: Icons.person_outline,
          action: FilledButton(
            onPressed: () => context.push('/login'),
            child: const Text('Sign in'),
          ),
        ),
      );
    }

    final tabBar = TabBar(
      controller: _controller,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      tabs: [
        for (final tab in _tabs)
          Tab(text: tab.label, icon: Icon(tab.icon, size: 18)),
      ],
    );

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            pinned: true,
            expandedHeight:
                kToolbarHeight + _heroHeight + tabBar.preferredSize.height,
            flexibleSpace: FlexibleSpaceBar(
              background: Padding(
                padding: EdgeInsets.only(
                  top: kToolbarHeight + MediaQuery.paddingOf(context).top,
                  bottom: tabBar.preferredSize.height,
                ),
                child: _Hero(user: user),
              ),
            ),
            actions: [
              if (isAdmin)
                IconButton(
                  tooltip: 'Server admin',
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                  onPressed: () => context.push('/admin'),
                ),
              IconButton(
                tooltip: 'Change server',
                icon: const Icon(Icons.dns_outlined),
                onPressed: () => context.push('/server'),
              ),
            ],
            bottom: tabBar,
          ),
        ],
        body: TabBarView(
          controller: _controller,
          children: const [
            LibraryTab(kind: LibraryKind.watchlist),
            LibraryTab(kind: LibraryKind.favorites),
            HistoryTab(),
            RatingsTab(),
            SocialTab(),
            PreferencesTab(),
            ProfileTab(),
          ],
        ),
      ),
    );
  }
}

class _Hero extends ConsumerWidget {
  const _Hero({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final counts = ref.watch(followCountsProvider).valueOrNull;
    final serverUrl = ref.watch(currentServerUrlProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: theme.colorScheme.primary,
            backgroundImage: user.avatarUrl != null
                ? CachedNetworkImageProvider(user.avatarUrl!)
                : null,
            child: user.avatarUrl == null
                ? Text(user.initial,
                    style: TextStyle(
                        fontSize: 22, color: theme.colorScheme.onPrimary))
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(user.label,
                    style: theme.textTheme.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                  user.email,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (counts != null) ...[
                      Text(
                          '${counts.followers} followers · '
                          '${counts.following} following',
                          style: theme.textTheme.labelSmall),
                    ],
                    if (!user.emailVerified) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.error_outline,
                          size: 14, color: theme.colorScheme.error),
                      const SizedBox(width: 2),
                      Text('Email not verified',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.colorScheme.error)),
                    ],
                  ],
                ),
                if (serverUrl != null)
                  Text(
                    Uri.parse(serverUrl).host,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.hintColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
