import 'package:flutter/material.dart';
import 'package:flutter_chrome_cast/entities.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cast/cast_service.dart';
import '../../shared/widgets/async_states.dart';
import '../../state/cast_providers.dart';

/// Device picker for casting: discovered receivers, and a disconnect action
/// once a session is up.
class CastSheet extends ConsumerStatefulWidget {
  const CastSheet({
    super.key,
    required this.rawUrl,
    required this.title,
    this.subtitle,
    this.posterUrl,
    this.startFrom = Duration.zero,
  });

  /// The stream URL as resolved from the backend — [CastService] wraps it in
  /// the proxy the receiver needs.
  final String rawUrl;
  final String title;
  final String? subtitle;
  final String? posterUrl;
  final Duration startFrom;

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

    final ok = await runGuarded(context, () async {
      final connected = await cast.connect(device);
      if (!connected) throw const _CastFailure('Could not connect to that device.');
      await cast.load(
        rawUrl: widget.rawUrl,
        title: widget.title,
        subtitle: widget.subtitle,
        posterUrl: widget.posterUrl,
        startFrom: widget.startFrom,
      );
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
    final hasSession = ref.watch(castSessionProvider).valueOrNull != null;

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
                Text('Cast to a device',
                    style: Theme.of(context).textTheme.titleMedium),
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
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      for (final device in devices)
                        ListTile(
                          enabled: !_connecting,
                          leading: const Icon(Icons.tv),
                          title: Text(device.friendlyName),
                          subtitle: device.modelName != null
                              ? Text(device.modelName!)
                              : null,
                          onTap: _connecting ? null : () => _connect(cast, device),
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
