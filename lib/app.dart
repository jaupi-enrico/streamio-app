import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'routing/app_router.dart';
import 'shared/theme/app_theme.dart';
import 'state/server_config_provider.dart';
import 'state/startup.dart';

class StreamioApp extends ConsumerWidget {
  const StreamioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Resume/flush work that needs a configured server. Watched (not read)
    // so it re-runs if the user points the app at a different server.
    if (ref.watch(currentServerUrlProvider) != null) {
      ref.watch(startupTasksProvider);
    }

    return MaterialApp.router(
      title: 'Streamio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
