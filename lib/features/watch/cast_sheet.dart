import 'package:flutter/material.dart';
import 'package:flutter_chrome_cast/entities.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/cast/cast_service.dart';
import '../../shared/widgets/async_states.dart';
import '../../state/cast_providers.dart';

/// Device picker for casting: discovered receivers, and a disconnect action
/// once a session is up.
///
/// **This sheet picks a device; it does not load the stream.** The load is
/// owned by whoever opened it and fires off the session becoming active —
/// the same shape as the web sender, where `onCastSessionStarted` calls
/// `loadCastMedia` for `SESSION_STARTED` *and* `SESSION_RESUMED`. Keeping the
/// load here instead made it reachable only by picking a device, so a session
/// that already existed (the receiver launched on the TV, sitting idle with
/// nothing playing) had no way to be given a stream.
///
/// [onCastHere] covers the one case the session listener cannot see: tapping
/// the device that is *already* connected changes no session, so the request
/// to play has to be passed on explicitly. It is null when the sheet is opened
/// from a screen with no stream of its own — the home screen's now-casting
/// button — and the connected device is then simply not tappable, since there
/// is nothing to hand it.
class CastSheet extends ConsumerStatefulWidget {
  const CastSheet({super.key, this.onCastHere});

  /// Load the current stream onto the session that is already running.
  final Future<void> Function()? onCastHere;

  @override
  ConsumerState<CastSheet> createState() => _CastSheetState();
}

class _CastSheetState extends ConsumerState<CastSheet> {
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    // Discovery is only run while this sheet is open: it's a battery and
    // network cost with nothing to show for it otherwise.
    ref.read(castServiceProvider).startDiscovery();
  }

  @override
  void dispose() {
    ref.read(castServiceProvider).stopDiscovery();
    super.dispose();
  }

  Future<void> _connect(CastService cast, GoogleCastDevice device) async {
    setState(() => _connecting = true);

    // A session on this device already exists when the receiver was launched
    // before anything was cast to it — the TV shows the idle Streamio
    // receiver, waiting for a stream. Starting a *second* session on a device
    // that already has one fails, and no session event would fire for the
    // opener to react to, so the play request is handed over directly.
    final current = ref.read(castSessionProvider).value;
    final alreadyHere = current != null && current.device == device;

    final ok = await runGuarded(context, () async {
      if (alreadyHere) {
        await widget.onCastHere?.call();
        return;
      }
      final connected = await cast.connect(device);
      if (!connected) {
        throw const _CastFailure('Could not connect to that device.');
      }
      // The stream follows from the session going active; see the class doc.
    }, successMessage: 'Casting to ${device.friendlyName}');

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cast = ref.watch(castServiceProvider);
    final devicesAsync = ref.watch(castDevicesProvider);
    final hasSession = ref.watch(castSessionProvider).value != null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.cast),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Cast to a device',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                // "No devices found" is most often a receiver-id mismatch, so
                // the place to fix it is one tap from where you notice.
                IconButton(
                  tooltip: 'Chromecast settings',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push('/settings/cast');
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (hasSession) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cast_connected),
                title: const Text('Stop casting'),
                onTap: () async {
                  await cast.disconnect();
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
              const Divider(),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: devicesAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => ErrorState(error: error, scrollable: false),
                data: (devices) {
                  if (devices.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Looking for devices… Make sure your Chromecast is on the '
                        'same network.',
                      ),
                    );
                  }
                  final connected = ref.watch(castSessionProvider).value?.device;
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      for (final device in devices)
                        ListTile(
                          enabled: !_connecting,
                          leading: Icon(device == connected
                              ? Icons.cast_connected
                              : Icons.tv),
                          title: Text(device.friendlyName),
                          // The connected device stays tappable on purpose:
                          // the receiver can be running with nothing playing
                          // on it, and this is how the stream gets there. With
                          // no stream to offer it, it is a label instead.
                          subtitle: Text(
                            device == connected
                                ? (widget.onCastHere != null
                                    ? 'Connected — tap to play this here'
                                    : 'Connected')
                                : (device.modelName ?? ''),
                          ),
                          onTap: _connecting ||
                                  (device == connected &&
                                      widget.onCastHere == null)
                              ? null
                              : () => _connect(cast, device),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CastFailure implements Exception {
  const _CastFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
