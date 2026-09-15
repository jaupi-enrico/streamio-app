import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/account/account_screen.dart';
import '../features/admin/admin_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/auth/tv_login_screen.dart';
import '../features/auth/verify_email_screen.dart';
import '../features/catalog/catalog_screen.dart';
import '../features/details/details_screen.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/home/home_screen.dart';
import '../features/providers/providers_screen.dart';
import '../features/rooms/rooms_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/cast_settings_screen.dart';
import '../features/setup/server_setup_screen.dart';
import '../features/watch/watch_screen.dart';
import '../state/auth_providers.dart';
import '../state/server_config_provider.dart';
import 'app_shell.dart';

/// The only routes reachable without a session. Everything else — browsing,
/// details, playback, downloads — requires a signed-in user.
///
/// `/reset-password` and `/verify-email` are here because they are opened from
/// an emailed link, which may well arrive before the user has ever signed in
/// on this device.
const _publicPrefixes = <String>[
  '/login',
  '/register',
  '/reset-password',
  '/verify-email',
  '/tv-login',
];

/// Public routes that stop making sense once you're signed in.
const _signedOutOnlyPrefixes = <String>['/login', '/register', '/tv-login'];

/// The router's own navigator, for routes that must escape the shell.
///
/// Note for anything living *outside* the Router — like `UpdateGate`, wrapped
/// around `child` in `MaterialApp.router`'s `builder`: this key is not a way
/// to show a dialog from out there. `showDialog` pushes a pageless route, and
/// a pageless route is discarded when the page it is attached to is removed,
/// which this router does routinely (splash → home on bootstrap, any redirect
/// re-evaluation). Draw the overlay into your own subtree instead.
final rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final serverUrl = ref.read(serverBaseUrlProvider);
      final location = state.matchedLocation;

      // Still reading shared_preferences — hold on the splash rather than
      // bouncing the user to /setup and back.
      if (serverUrl.isLoading) return location == '/splash' ? null : '/splash';

      final hasServer = serverUrl.value != null;
      if (!hasServer) return location == '/setup' ? null : '/setup';

      // Repointing at another install stays reachable logged out: aiming at
      // the wrong server is exactly what stops you from signing in.
      if (location == '/server') return null;

      // Still restoring the stored session. Hold on the splash rather than
      // flashing the login screen at someone who is already signed in.
      if (!ref.read(authBootstrappedProvider)) {
        return location == '/splash' ? null : '/splash';
      }

      if (!ref.read(isSignedInProvider)) {
        if (_publicPrefixes.any(location.startsWith)) return null;
        return '/login?redirect=${Uri.encodeComponent(state.uri.toString())}';
      }

      // Signed in: the splash, setup and the sign-in screens are all done.
      if (location == '/splash' ||
          location == '/setup' ||
          _signedOutOnlyPrefixes.any(location.startsWith)) {
        return '/';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const _SplashScreen()),
      GoRoute(
        path: '/setup',
        builder: (context, state) => const ServerSetupScreen(),
      ),
      GoRoute(
        path: '/server',
        builder: (context, state) => const ServerSetupScreen(isInitialSetup: false),
      ),

      // ── Auth (full-screen, outside the shell) ──────────────
      GoRoute(
        path: '/login',
        builder: (context, state) =>
            LoginScreen(redirectTo: state.uri.queryParameters['redirect']),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) =>
            RegisterScreen(redirectTo: state.uri.queryParameters['redirect']),
      ),
      // Sign-in for a device with no browser to open the OAuth consent page —
      // an Android TV. See `features/auth/tv_login_screen.dart`.
      GoRoute(
        path: '/tv-login',
        builder: (context, state) =>
            TvLoginScreen(redirectTo: state.uri.queryParameters['redirect']),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) =>
            ResetPasswordScreen(token: state.uri.queryParameters['token']),
      ),
      GoRoute(
        path: '/verify-email',
        builder: (context, state) =>
            VerifyEmailScreen(token: state.uri.queryParameters['token']),
      ),

      // ── Full-screen content routes ─────────────────────────
      GoRoute(
        path: '/details/:provider/:showId',
        builder: (context, state) => DetailsScreen(
          provider: state.pathParameters['provider']!,
          showId: Uri.decodeComponent(state.pathParameters['showId']!),
        ),
      ),
      GoRoute(
        path: '/watch/:provider/:id',
        builder: (context, state) {
          final query = state.uri.queryParameters;
          return WatchScreen(
            provider: state.pathParameters['provider']!,
            id: Uri.decodeComponent(state.pathParameters['id']!),
            contentType: query['contentType'],
            showId: query['showId'],
            title: query['title'],
            episodeLabel: query['episodeLabel'],
            roomCode: query['room'],
            downloadId: query['download'],
            startSeconds: int.tryParse(query['t'] ?? ''),
          );
        },
      ),
      GoRoute(path: '/providers', builder: (context, state) => const ProvidersScreen()),
      GoRoute(path: '/rooms', builder: (context, state) => const RoomsScreen()),
      GoRoute(path: '/admin', builder: (context, state) => const AdminScreen()),
      GoRoute(
        path: '/settings/cast',
        builder: (context, state) => const CastSettingsScreen(),
      ),

      // ── Tabbed shell ───────────────────────────────────────
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
          GoRoute(
            path: '/catalog',
            builder: (context, state) => CatalogScreen(
              initialGenreId: state.uri.queryParameters['genre'],
            ),
          ),
          GoRoute(
            path: '/search',
            builder: (context, state) =>
                SearchScreen(initialQuery: state.uri.queryParameters['q']),
          ),
          GoRoute(path: '/downloads', builder: (context, state) => const DownloadsScreen()),
          GoRoute(
            path: '/account',
            builder: (context, state) =>
                AccountScreen(initialTab: state.uri.queryParameters['tab']),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => _RouteErrorScreen(location: state.uri.toString()),
  );
});

/// Bridges the two Riverpod values the redirect reads into a [Listenable]
/// GoRouter can subscribe to, so logging in/out or changing servers
/// re-evaluates the guards immediately.
///
/// The notify is deferred to a microtask rather than fired inline from
/// `ref.listen`. `authProvider` changing is what wakes this up, but the
/// redirect below reads *derived* providers (`authBootstrappedProvider`,
/// `isSignedInProvider`), not `authProvider` itself — and calling
/// `notifyListeners()` synchronously re-enters GoRouter's redirect from
/// inside `authProvider`'s own notification pass, before those derived
/// providers have recomputed against the new state. That race let a restore
/// that just succeeded read back `isSignedInProvider == false`, GoRouter
/// would settle on /login, and — with no further state change left to fire a
/// second notify — it never got a second chance to leave. Posting to a
/// microtask runs the redirect after Riverpod's notification pass (and
/// everything it recomputes) has finished.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    void scheduleNotify() => scheduleMicrotask(notifyListeners);
    _subscriptions = [
      ref.listen(serverBaseUrlProvider, (_, __) => scheduleNotify()),
      ref.listen(authProvider, (_, __) => scheduleNotify()),
    ];
  }

  late final List<ProviderSubscription<Object?>> _subscriptions;

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.close();
    }
    super.dispose();
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _RouteErrorScreen extends StatelessWidget {
  const _RouteErrorScreen({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore_off_outlined, size: 48),
              const SizedBox(height: 12),
              Text('No screen for $location', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go('/'),
                child: const Text('Go home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
