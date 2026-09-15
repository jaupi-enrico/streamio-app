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
class CastReceiverOverrideNotifier extends Notifier<AsyncValue<String?>> {
  @override
  AsyncValue<String?> build() {
    _restore();
    return const AsyncValue.loading();
  }

  Future<void> _restore() async {
    try {
      final appId = await CastReceiverConfig.read();
      if (!ref.mounted) return;
      state = AsyncValue.data(appId);
    } catch (err, stack) {
      if (!ref.mounted) return;
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

final castReceiverOverrideProvider =
    NotifierProvider<CastReceiverOverrideNotifier, AsyncValue<String?>>(
        CastReceiverOverrideNotifier.new);

final castDevicesProvider = StreamProvider.autoDispose<List<GoogleCastDevice>>((ref) {
  return ref.watch(castServiceProvider).devicesStream;
});

final castSessionProvider = StreamProvider<GoogleCastSession?>((ref) {
  return ref.watch(castServiceProvider).sessionStream;
});

/// The receiver's own view of what it is doing — see `docs/protocol.md` in the
/// `cast-receiver` repo. Null until the first `STATE` arrives.
///
/// The receiver broadcasts on every phase change and every 5s while playing,
/// which is *identity* resolution, not transport resolution: the panel's
/// progress bar runs on [castPositionProvider] instead, and this supplies the
/// title, episode and track lists. `HELLO` is sent on subscribe so the panel
/// doesn't open on a blank five-second wait.
///
/// Kept alive rather than autoDispose: the receiver keeps playing while the
/// panel is closed, and the history writer reads this the whole time.
final castStateProvider = StreamProvider<CastState?>((ref) {
  final cast = ref.watch(castServiceProvider);
  cast.hello();
  // …and again once a session actually exists. The first HELLO is usually
  // sent into nothing: this provider is created as soon as any screen wants a
  // `STATE`, which is well before a receiver is connected, and a control
  // message with no session has nowhere to go. The receiver does broadcast on
  // its own every 5s, so the only cost of the lost one is opening the panel on
  // a blank wait — which is exactly what this exists to avoid.
  ref.listen(castSessionProvider, (previous, next) {
    if (next.value != null && previous?.value == null) cast.hello();
  });
  return cast.stateStream;
});

/// Playback position, updated far more often than the 5s `STATE` broadcast.
final castPositionProvider = StreamProvider.autoDispose<Duration>((ref) {
  return ref.watch(castServiceProvider).positionStream;
});

/// Transport status from the standard media channel — player state and volume.
/// Available even against a receiver too old for the control channel, which is
/// why play/pause is driven off this and not off [castStateProvider].
final castMediaStatusProvider =
    StreamProvider.autoDispose<GoggleCastMediaStatus?>((ref) {
  return ref.watch(castServiceProvider).mediaStatusStream;
});
