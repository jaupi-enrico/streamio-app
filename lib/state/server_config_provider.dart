import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/server_config.dart';

/// The backend origin every request is built on, or null when the app has
/// never been pointed at a server (first launch → /setup).
///
/// This sits at the root of the provider graph: changing it disposes the
/// [ApiClient] and, transitively, every content/account provider, so the whole
/// app re-fetches against the new server without a restart.
class ServerBaseUrlNotifier extends Notifier<AsyncValue<String?>> {
  @override
  AsyncValue<String?> build() {
    _restore();
    return const AsyncValue.loading();
  }

  Future<void> _restore() async {
    try {
      final url = await ServerConfig.read();
      if (!ref.mounted) return;
      state = AsyncValue.data(url);
    } catch (err, stack) {
      if (!ref.mounted) return;
      state = AsyncValue.error(err, stack);
    }
  }

  /// [url] must already be normalized (see [ServerConfig.normalize]).
  Future<void> set(String url) async {
    await ServerConfig.write(url);
    state = AsyncValue.data(url);
  }

  Future<void> clear() async {
    await ServerConfig.clear();
    state = const AsyncValue.data(null);
  }
}

final serverBaseUrlProvider =
    NotifierProvider<ServerBaseUrlNotifier, AsyncValue<String?>>(
        ServerBaseUrlNotifier.new);

/// Convenience view: the configured URL, or null while loading/unset.
final currentServerUrlProvider = Provider<String?>((ref) {
  return ref.watch(serverBaseUrlProvider).value;
});
