import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/tv.dart';
import '../shared/widgets/app_logo.dart';
import '../state/auth_providers.dart';

/// Chrome around the five top-level destinations.
///
/// Mirrors the web frontend's responsive nav: a bottom bar on phones, a top
/// nav row from 900px up (the same breakpoint `home.css` switches at), and a
/// persistent D-pad-navigable side rail on Android TV (see [isTv]).
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static const _destinations = <_Destination>[
    _Destination('/', 'Home', Icons.home_outlined, Icons.home),
    _Destination(
        '/catalog', 'Catalog', Icons.grid_view_outlined, Icons.grid_view),
    _Destination('/search', 'Search', Icons.search_outlined, Icons.search),
    _Destination(
        '/downloads', 'Downloads', Icons.download_outlined, Icons.download),
    _Destination('/account', 'Account', Icons.person_outline, Icons.person),
  ];

  static int _indexOf(String location) {
    // Longest match first so '/catalog' doesn't get swallowed by '/'.
    var best = 0;
    var bestLength = 0;
    for (var i = 0; i < _destinations.length; i++) {
      final path = _destinations[i].path;
      final matches = path == '/' ? location == '/' : location.startsWith(path);
      if (matches && path.length >= bestLength) {
        best = i;
        bestLength = path.length;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    final index = _indexOf(location);
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    void go(int i) => context.go(_destinations[i].path);

    if (isTv(context)) {
      return Scaffold(
        body: Row(
          children: [
            _TvNavRail(
              destinations: _destinations,
              selectedIndex: index,
              onSelected: go,
            ),
            Expanded(child: FocusTraversalGroup(child: child)),
          ],
        ),
      );
    }

    if (isWide) {
      return Scaffold(
        appBar: _WideNavBar(
          destinations: _destinations,
          selectedIndex: index,
          onSelected: go,
        ),
        body: child,
      );
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: go,
        destinations: [
          for (final destination in _destinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: destination.label,
            ),
        ],
      ),
    );
  }
}

/// Persistent left-edge nav for D-pad use: up/down cycles destinations, right
/// hands focus into the content pane. A plain [NavigationRail] doesn't expose
/// per-item autofocus, so this is a small hand-rolled equivalent instead.
class _TvNavRail extends StatelessWidget {
  const _TvNavRail({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_Destination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FocusTraversalGroup(
      child: Container(
        width: 96,
        color: theme.colorScheme.surface,
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < destinations.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: _TvNavRailItem(
                    destination: destinations[i],
                    selected: i == selectedIndex,
                    autofocus: i == selectedIndex,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvNavRailItem extends StatefulWidget {
  const _TvNavRailItem({
    required this.destination,
    required this.selected,
    required this.autofocus,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final bool autofocus;
  final VoidCallback onTap;

  @override
  State<_TvNavRailItem> createState() => _TvNavRailItemState();
}

class _TvNavRailItemState extends State<_TvNavRailItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.selected ? theme.colorScheme.primary : theme.hintColor;
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onFocusChange: (focused) => setState(() => _focused = focused),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap();
          return null;
        }),
      },
      mouseCursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 80,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused ? theme.colorScheme.primary : Colors.transparent,
              width: 2,
            ),
            color: widget.selected
                ? theme.colorScheme.primary.withValues(alpha: 0.12)
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.selected
                    ? widget.destination.selectedIcon
                    : widget.destination.icon,
                color: color,
              ),
              const SizedBox(height: 4),
              Text(
                widget.destination.label,
                style: theme.textTheme.labelSmall?.copyWith(color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Destination {
  const _Destination(this.path, this.label, this.icon, this.selectedIcon);

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _WideNavBar extends ConsumerWidget implements PreferredSizeWidget {
  const _WideNavBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_Destination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);

    return AppBar(
      toolbarHeight: 64,
      titleSpacing: 24,
      title: Row(
        children: [
          const AppLogo(size: 28),
          const SizedBox(width: 10),
          Text(
            'STREAMIO',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.primary,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(width: 32),
          for (var i = 0; i < destinations.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TextButton(
                onPressed: () => onSelected(i),
                style: TextButton.styleFrom(
                  foregroundColor: i == selectedIndex
                      ? theme.colorScheme.primary
                      : theme.textTheme.bodyMedium?.color,
                ),
                child: Text(destinations[i].label),
              ),
            ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Providers',
          onPressed: () => context.push('/providers'),
          icon: const Icon(Icons.tune),
        ),
        IconButton(
          tooltip: 'Watch parties',
          onPressed: () => context.push('/rooms'),
          icon: const Icon(Icons.groups_outlined),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 16, left: 8),
          child: user == null
              ? TextButton(
                  onPressed: () => context.push('/login'),
                  child: const Text('Log in'),
                )
              : CircleAvatar(
                  radius: 16,
                  backgroundColor: theme.colorScheme.primary,
                  child: Text(
                    user.initial,
                    style: TextStyle(color: theme.colorScheme.onPrimary),
                  ),
                ),
        ),
      ],
    );
  }
}
