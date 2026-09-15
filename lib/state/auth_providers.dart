import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/models/models.dart';
import 'api_providers.dart';

/// Who's signed in, or null when logged out.
///
/// The whole app is gated on this: the router keeps every screen except the
/// auth flow and server setup unreachable while it is null, so `loading` here
/// means "still deciding", not "signed out" — see `routing/app_router.dart`.
class AuthNotifier extends Notifier<AsyncValue<AppUser?>> {
  @override
  AsyncValue<AppUser?> build() {
    // Riverpod reuses the notifier instance across rebuilds, so this has to be
    // reset by hand: pointing the app at another server puts the session back
    // to "still deciding", which is what holds the router on the splash.
    _bootstrapped = false;

    // A 401 that survives one refresh means the session is gone for good.
    // No server yet means there is nothing to be signed out of.
    final client = watchApiClientOrNull(ref);
    if (client != null) {
      final subscription = client.onAuthLost.listen((_) => onSessionLost());
      ref.onDispose(subscription.cancel);
    }

    _restore();
    return const AsyncValue.loading();
  }

  bool _bootstrapped = false;

  /// False until the stored session has been examined once.
  ///
  /// The router needs this to tell "we don't know yet" from "signed out": the
  /// former holds on the splash, the latter sends you to /login. A plain
  /// `isLoading` can't say which, because signing in goes through `loading`
  /// too — and bouncing to the splash mid-submit would eat the login form.
  bool get isBootstrapped => _bootstrapped;

  Future<void> _restore() async {
    final user = await _restoreUser();
    // Riverpod 3 rebuilds a Notifier (and throws on a write to the old one)
    // when a dependency changes — here, pointing the app at another server
    // mid-restore.
    if (!ref.mounted) return;
    _bootstrapped = true;
    state = AsyncValue.data(user);
  }

  Future<AppUser?> _restoreUser() async {
    final client = readApiClientOrNull(ref);
    if (client == null) return null;

    try {
      if (!await client.tokens.hasSession) {
        developer.log('restore: no session in the keystore', name: 'auth');
        return null;
      }
      return await _fetchUser();
    } on SessionExpiredException {
      developer.log('restore: session rejected (refresh dead)', name: 'auth');
      return null;
    } catch (err, stack) {
      // Offline or the server is down. The tokens are still there and nothing
      // said they were rejected, so fall back to the last profile we saw
      // rather than locking the user out of their downloads over a blip.
      // Screens that need a fresh user retry via [refresh].
      developer.log('restore: /me failed, falling back to cached user',
          name: 'auth', error: err, stackTrace: stack);
      return _cachedUser(client);
    }
  }

  /// Fetches the profile and keeps a copy for offline restores.
  Future<AppUser> _fetchUser() async {
    final user = await ref.read(accountApiProvider).me();
    try {
      await ref
          .read(apiClientProvider)
          .tokens
          .saveCachedUser(jsonEncode(user.toJson()));
    } catch (_) {
      // A keystore write failure only costs us the offline fallback.
    }
    return user;
  }

  Future<AppUser?> _cachedUser(ApiClient client) async {
    try {
      final json = await client.tokens.cachedUser;
      if (json == null) return null;
      return AppUser.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _restore();
  }

  Future<void> login(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      await ref.read(authApiProvider).login(email, password);
      state = AsyncValue.data(await _fetchUser());
    } catch (err, stack) {
      state = AsyncValue.error(err, stack);
      rethrow;
    }
  }

  Future<void> register(String email, String password, {String? displayName}) async {
    state = const AsyncValue.loading();
    try {
      await ref
          .read(authApiProvider)
          .register(email, password, displayName: displayName);
      state = AsyncValue.data(await _fetchUser());
    } catch (err, stack) {
      state = AsyncValue.error(err, stack);
      rethrow;
    }
  }

  /// Completes the `streamio://auth?token=&refresh=` OAuth callback.
  Future<void> completeOAuth(Uri callback) async {
    state = const AsyncValue.loading();
    try {
      final ok = await ref.read(authApiProvider).completeOAuth(callback);
      if (!ok) throw const ApiException('The sign-in callback had no token.');
      state = AsyncValue.data(await _fetchUser());
    } catch (err, stack) {
      state = AsyncValue.error(err, stack);
      rethrow;
    }
  }

  /// Adopts the session a TV sign-in just landed in the keystore.
  ///
  /// The poll in `AuthApi.pollDeviceLogin` has already saved the tokens, so
  /// there is nothing to exchange here — this only fetches the profile and
  /// flips the router's guard, the same tail every other sign-in runs.
  Future<void> completeDeviceLogin() async {
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(await _fetchUser());
    } catch (err, stack) {
      state = AsyncValue.error(err, stack);
      rethrow;
    }
  }

  Future<void> logout() async {
    await ref.read(authApiProvider).logout();
    state = const AsyncValue.data(null);
  }

  /// Called when the API client gives up on refreshing a dead session.
  void onSessionLost() => state = const AsyncValue.data(null);
}

final authProvider =
    NotifierProvider<AuthNotifier, AsyncValue<AppUser?>>(AuthNotifier.new);

/// True once a user is known to be signed in. Used by the router's guard and
/// to decide whether to show library affordances.
final isSignedInProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).value != null;
});

/// Whether the stored session has been resolved yet — see
/// [AuthNotifier.isBootstrapped]. Depends on [authProvider] so it recomputes
/// when the first restore lands.
final authBootstrappedProvider = Provider<bool>((ref) {
  ref.watch(authProvider);
  return ref.read(authProvider.notifier).isBootstrapped;
});

final currentUserProvider = Provider<AppUser?>((ref) {
  return ref.watch(authProvider).value;
});
