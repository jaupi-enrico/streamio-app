import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:streamio/routing/app_shell.dart';
import 'package:streamio/shared/theme/app_theme.dart';
import 'package:streamio/shared/tv.dart';

/// `ShellRoute` puts each page inside a nested [Navigator], and therefore
/// inside its own [FocusScope]. Directional traversal never crosses a focus
/// scope boundary, so without the escape hatch in [AppShell] the top row of
/// the page is a ceiling: no number of D-pad presses reaches the nav chrome.
///
/// That is invisible on a touch device and total on a remote, which is
/// exactly the combination worth a test.
void main() {
  Widget harness({required List<String> pageItems}) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        ShellRoute(
          navigatorKey: GlobalKey<NavigatorState>(),
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => Scaffold(
                body: Column(
                  children: [
                    for (final label in pageItems)
                      FocusableActionDetector(child: Text(label)),
                  ],
                ),
              ),
            ),
            GoRoute(
              path: '/search',
              builder: (context, state) =>
                  const Scaffold(body: Text('search page')),
            ),
          ],
        ),
      ],
    );
    return ProviderScope(
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    );
  }

  /// The label of whatever currently holds focus, or the node's debug label
  /// for the nav items (which are identified by that).
  String? focusedLabel() {
    final node = FocusManager.instance.primaryFocus;
    final ctx = node?.context;
    if (ctx == null) return node?.debugLabel;
    String? found;
    void visit(Element e) {
      if (found != null) return;
      if (e.widget case final Text t) {
        found = t.data;
        return;
      }
      e.visitChildren(visit);
    }

    (ctx as Element).visitChildren(visit);
    return found ?? node?.debugLabel;
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  group('the wide top bar', () {
    testWidgets('is reachable from inside the page with the D-pad',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness(pageItems: ['card A', 'card B']));
      await tester.pumpAndSettle();

      // Down into the page, far enough to be well inside the nested scope.
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedLabel(), 'card B');

      // Back up: one press per card, then one more that has to cross the
      // scope wall into the app bar.
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedLabel(), 'card A');
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedLabel(), 'Home',
          reason: 'focus never escaped the page\'s FocusScope');
    });

    testWidgets('hands focus back into the page on the way down',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness(pageItems: ['card A', 'card B']));
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedLabel(), 'Home');

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedLabel(), 'card A');
    });
  });

  group('the TV rail', () {
    setUp(() => TvPlatform.debugIsTv = true);
    tearDown(() => TvPlatform.debugIsTv = false);

    testWidgets('is reachable by pressing left out of the page',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness(pageItems: ['card A']));
      await tester.pumpAndSettle();

      // The rail autofocuses the current destination; go right into the page
      // first, which works unaided (the rail is in the root scope).
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedLabel(), 'card A');

      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusedLabel(), 'Home',
          reason: 'focus never escaped the page\'s FocusScope back to the rail');
    });

    testWidgets('carries the routes the top bar would otherwise hide',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness(pageItems: ['card A']));
      await tester.pumpAndSettle();

      // The rail replaces the top bar, whose IconButtons are the only other
      // route to these.
      expect(find.text('Providers'), findsOneWidget);
      expect(find.text('Parties'), findsOneWidget);
    });
  });
}
