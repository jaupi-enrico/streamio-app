import 'package:flutter_chrome_cast/entities.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/cast/cast_service.dart';
import '../core/config/cast_receiver_config.dart';
import 'api_providers.dart';

final castServiceProvider = Provider<CastService>((ref) {
  return CastService(ref.watch(contentApiProvider));
});

/// Whether Cast is usable at all: a supported platform, plus a Cast SDK that
/// started. False keeps the Cast button hidden entirely.
///
/// Note this no longer depends on the server answering `/api/cast-config` —
/// see [CastService.initialize].
final castAvailableProvider = FutureProvider<bool>((ref) async {
  if (!CastService.isSupported) return false;
  // Re-resolve after the receiver id is edited: if Cast previously failed to
  // start there is a chance the new id gets it going without a restart.
  ref.watch(castReceiverOverrideProvider);
  return ref.watch(castServiceProvider).initialize();
});

/// The resolved receiver id / proxy base, once [castAvailableProvider] has run.
/// Null before initialization is attempted.
final castConfigInfoProvider = Provider<CastConfigInfo?>((ref) {
  ref.watch(castAvailableProvider);
  return ref.watch(castServiceProvider).config;
});

/// The device-local receiver id override, or null when the server's id applies.
class CastReceiverOverrideNotifier extends StateNotifier<AsyncValue<String?>> {
  CastReceiverOverrideNotifier() : super(const AsyncValue.loading()) {
    _restore();
  }

  Future<void> _restore() async {
    try {
      state = AsyncValue.data(await CastReceiverConfig.read());
    } catch (err, stack) {
      state = AsyncValue.error(err, stack);
    }
  }

  /// [appId] must already be normalized (see [CastReceiverConfig.normalize]).
  Future<void> set(String appId) async {
    await CastReceiverConfig.write(appId);
    state = AsyncValue.data(appId);
  }

  Future<void> clear() async {
    await CastReceiverConfig.clear();
    state = const AsyncValue.data(null);
  }
}

final castReceiverOverrideProvider = StateNotifierProvider<
    CastReceiverOverrideNotifier,
    AsyncValue<String?>>((ref) => CastReceiverOverrideNotifier());

final castDevicesProvider = StreamProvider.autoDispose<List<GoogleCastDevice>>((ref) {
  return ref.watch(castServiceProvider).devicesStream;
});

final castSessionProvider = StreamProvider<GoogleCastSession?>((ref) {
  return ref.watch(castServiceProvider).sessionStream;
});
