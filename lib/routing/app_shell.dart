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
class AppShell extends ConsumerStatefulWidget {
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

  /// Reachable from the top bar's [IconButton]s on touch/desktop. The TV rail
  /// replaces that bar entirely, so they have to appear there too or they
  /// become unreachable with a remote — there is no other route to them.
  static const _extras = <_Destination>[
    _Destination('/providers', 'Providers', Icons.tune, Icons.tune),
    _Destination('/rooms', 'Parties', Icons.groups_outlined, Icons.groups),
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
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// One per nav item, kept on the state so they survive the rebuild every
  /// route change causes — [_escapeToNav] has to be able to hand focus to a
  /// specific one from outside the widget that owns it.
  late final List<FocusNode> _navFocusNodes = List.generate(
    AppShell._destinations.length + AppShell._extras.length,
    (i) => FocusNode(debugLabel: 'nav $i'),
  );

  @override
  void dispose() {
    for (final node in _navFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  /// Puts focus on the nav item for the current route.
  ///
  /// See [_DirectionalEscapeAction] for why this can't be left to ordinary
  /// directional traversal.
  void _escapeToNav(int index) {
    if (index < 0 || index >= _navFocusNodes.length) return;
    _navFocusNodes[index].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final index = AppShell._indexOf(location);
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    void go(int i) => context.go(AppShell._destinations[i].path);

    // ── The scope wall ───────────────────────────────────────
    //
    // `ShellRoute` has its own navigatorKey, so [widget.child] is a nested
    // [Navigator] and each page inside it lives in that route's own
    // [FocusScope]. Directional traversal never crosses a focus scope
    // boundary: `inDirection` only ever considers `nearestScope`'s
    // descendants, and from inside the page that scope stops short of the
    // nav chrome. So no number of D-pad presses could ever reach the top bar
    // or the side rail — the topmost row of the page was simply the ceiling.
    //
    // (The reverse works unaided: the nav lives in the *root* scope, whose
    // descendants do include the nested one, so pressing back into the page
    // needs no help.)
    //
    // Overriding [DirectionalFocusIntent] here catches the presses that
    // traversal declined to act on and hands focus across the wall by hand.
    // This sits below Flutter's app-level default action and above the page,
    // so it wins for anything focused inside the page — but stays below
    // [EditableText]'s own action, which keeps arrow keys working as caret
    // movement inside a text field (see the shortcuts in app.dart for how a
    // remote gets *out* of one).
    Widget content(TraversalDirection escapeDirection) => Actions(
          actions: <Type, Action<Intent>>{
            DirectionalFocusIntent: _DirectionalEscapeAction(
              escapeDirection: escapeDirection,
              onEscape: () => _escapeToNav(index),
            ),
          },
          child: widget.child,
        );

    if (isTv(context)) {
      return Scaffold(
        body: Row(
          children: [
            _TvNavRail(
              destinations: AppShell._destinations,
              extras: AppShell._extras,
              selectedIndex: index,
              onSelected: go,
              onExtraSelected: (i) =>
                  context.push(AppShell._extras[i].path),
              focusNodes: _navFocusNodes,
            ),
            Expanded(
              child: FocusTraversalGroup(
                child: content(TraversalDirection.left),
              ),
            ),
          ],
        ),
      );
    }

    if (isWide) {
      return Scaffold(
        appBar: _WideNavBar(
          destinations: AppShell._destinations,
          selectedIndex: index,
          onSelected: go,
          focusNodes: _navFocusNodes,
        ),
        body: content(TraversalDirection.up),
      );
    }

    return Scaffold(
      // The bottom bar is a touch affordance on a phone; there's no D-pad
      // case to escape into, so the page keeps the default traversal.
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: go,
        destinations: [
          for (final destination in AppShell._destinations)
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

/// Moves focus the usual way, and when that fails *because there is nothing
/// left in this focus scope*, calls [onEscape].
///
/// A plain `Focus`/`Shortcuts` can't express this: the decision depends on
/// whether traversal actually moved, which is only known after trying.
/// [FocusNode.focusInDirection] reports exactly that.
class _DirectionalEscapeAction extends Action<DirectionalFocusIntent> {
  _DirectionalEscapeAction({
    required this.escapeDirection,
    required this.onEscape,
  });

  /// The one direction that leads to the nav chrome — up to a top bar, left
  /// to a side rail. Running out of room in any other direction is just the
  /// edge of the page and should do nothing.
  final TraversalDirection escapeDirection;
  final VoidCallback onEscape;

  @override
  void invoke(DirectionalFocusIntent intent) {
    final node = primaryFocus;
    if (node == null || node.context == null) return;
    if (node.focusInDirection(intent.direction)) return;
    if (intent.direction == escapeDirection) onEscape();
  }
}

/// Persistent left-edge nav for D-pad use: up/down cycles destinations, right
/// hands focus into the content pane. A plain [NavigationRail] doesn't expose
/// per-item autofocus, so this is a small hand-rolled equivalent instead.
class _TvNavRail extends StatelessWidget {
  const _TvNavRail({
    required this.destinations,
    required this.extras,
    required this.selectedIndex,
    required this.onSelected,
    required this.onExtraSelected,
    required this.focusNodes,
  });

  final List<_Destination> destinations;
  final List<_Destination> extras;

  /// Destinations first, then extras — the same order [AppShell] allocates
  /// them in, so index `i` here is index `i` there.
  final List<FocusNode> focusNodes;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final ValueChanged<int> onExtraSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FocusTraversalGroup(
      child: Container(
        width: 96,
        color: theme.colorScheme.surface,
        child: SafeArea(
          // Scrollable so a 720p panel (or a large system font) can still
          // reach the last item instead of overflowing it off the bottom.
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.sizeOf(context).height -
                    MediaQuery.paddingOf(context).vertical,
              ),
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
                        focusNode: focusNodes[i],
                        onTap: () => onSelected(i),
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Divider(height: 1),
                  ),
                  for (var i = 0; i < extras.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: _TvNavRailItem(
                        destination: extras[i],
                        selected: false,
                        autofocus: false,
                        focusNode: focusNodes[destinations.length + i],
                        onTap: () => onExtraSelected(i),
                      ),
                    ),
                ],
              ),
            ),
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
    required this.focusNode,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final bool autofocus;
  final FocusNode focusNode;
  final VoidCallback onTap;

  @override
  State<_TvNavRailItem> createState() => _TvNavRailItemState();
}

class _TvNavRailItemState extends State<_TvNavRailItem> {
  bool _focused = false;

  void _handleFocusChange(bool focused) {
    setState(() => _focused = focused);
    // The rail scrolls when it doesn't fit; a focused-but-offscreen item
    // would otherwise be unreachable-looking (see TvFocusable).
    if (!focused) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(context,
          alignment: 0.5, duration: const Duration(milliseconds: 200));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _focused
        ? theme.colorScheme.onPrimary
        : widget.selected
            ? theme.colorScheme.primary
            : theme.hintColor;
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: _handleFocusChange,
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
            // Filled solid while focused rather than tinted: from across a
            // room a 2px outline on a dark rail is not a legible answer to
            // "which item will the OK button press?".
            color: _focused
                ? theme.colorScheme.primary
                : widget.selected
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
    required this.focusNodes,
  });

  final List<_Destination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// Only the first [destinations.length] are used here; the extras are
  /// [IconButton]s in `actions` rather than nav entries.
  final List<FocusNode> focusNodes;

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
                focusNode: focusNodes[i],
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
