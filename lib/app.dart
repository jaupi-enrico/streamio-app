import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'routing/app_router.dart';
import 'shared/theme/app_theme.dart';
import 'shared/tv.dart';
import 'shared/widgets/update_gate.dart';
import 'state/server_config_provider.dart';
import 'state/startup.dart';
import 'state/update_providers.dart';

class StreamioApp extends ConsumerWidget {
  const StreamioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Resume/flush work that needs a configured server. Watched (not read)
    // so it re-runs if the user points the app at a different server.
    if (ref.watch(currentServerUrlProvider) != null) {
      ref.watch(startupTasksProvider);
      // Starts listening for 426s immediately, so one raised mid-session is
      // caught even if the launch check said this build was fine.
      ref.watch(clientOutdatedProvider);
    }

    return MaterialApp.router(
      title: 'Streamio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: ref.watch(appRouterProvider),
      // Wraps every route: the version policy applies app-wide, and the
      // blocked case has to be able to replace whatever is on screen.
      builder: (context, child) => _TvTextFieldEscape(
        child: UpdateGate(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

/// Lets a D-pad leave a focused text field.
///
/// [EditableText] installs its own `DirectionalFocusIntent` handler
/// ([DirectionalFocusAction.forTextField]) which, by design, *ignores*
/// intents whose `ignoreTextFields` is true — and that's what Flutter's
/// app-level arrow-key bindings send, because on a keyboard the arrows
/// belong to the caret and Tab moves focus. A remote has no Tab: once
/// focus landed in the search box or a login field, every direction was
/// swallowed and the only way on was the Back button. Sign-in, with two
/// fields and a button, was not completable at all.
///
/// Rebinding the vertical arrows to the same intent with
/// `ignoreTextFields: false` makes that same handler move focus instead.
/// This `Shortcuts` sits inside `WidgetsApp`'s [DefaultTextEditingShortcuts]
/// and so is consulted first, and only the vertical pair is taken — left and
/// right stay caret movement, which is how you edit what you typed.
///
/// TV-only: on a keyboard the existing behaviour is correct and Tab works.
class _TvTextFieldEscape extends StatelessWidget {
  const _TvTextFieldEscape({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isTv(context)) return child;
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowUp):
            DirectionalFocusIntent(TraversalDirection.up,
                ignoreTextFields: false),
        SingleActivator(LogicalKeyboardKey.arrowDown):
            DirectionalFocusIntent(TraversalDirection.down,
                ignoreTextFields: false),
      },
      child: child,
    );
  }
}
