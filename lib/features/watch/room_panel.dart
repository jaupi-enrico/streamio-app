import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Prefixed: `Share` is also one of our own models (a shared title).
import 'package:share_plus/share_plus.dart' as share_plus;

import '../../core/api/room_socket.dart';
import '../../core/models/models.dart';
import '../../shared/widgets/async_states.dart';
import '../../state/api_providers.dart';
import '../../state/auth_providers.dart';
import '../../state/server_config_provider.dart';

/// The in-player watch-party panel: the room code, an invite link, who's
/// here, and the socket that keeps everyone's playback in step.
///
/// Echo suppression works the same way it does in `watch.js`: applying a
/// remote state sets a short-lived guard, and only local play/pause/seek
/// inside the guard window is skipped — otherwise every applied update would
/// bounce straight back to the room as if the user had done it.
class RoomPanel extends ConsumerStatefulWidget {
  const RoomPanel({
    super.key,
    required this.code,
    required this.onRemoteState,
    required this.localPosition,
    required this.localPlaying,
  });

  final String code;
  final Future<void> Function(RoomState state) onRemoteState;
  final Duration Function() localPosition;
  final bool Function() localPlaying;

  @override
  ConsumerState<RoomPanel> createState() => _RoomPanelState();
}

class _RoomPanelState extends ConsumerState<RoomPanel> {
  static const _echoGuard = Duration(milliseconds: 1200);
  static const _broadcastInterval = Duration(seconds: 5);

  RoomConnection? _connection;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Timer? _broadcastTimer;
  DateTime? _guardUntil;

  Room? _room;
  List<RoomMember> _members = const [];
  bool _connected = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final room = await ref.read(roomsApiProvider).get(widget.code);
      if (!mounted) return;
      setState(() {
        _room = room;
        _members = room.members;
      });

      final connection =
          RoomConnection(client: ref.read(apiClientProvider), code: widget.code);
      _connection = connection;

      _subscriptions.addAll([
        connection.stateUpdates.listen(_applyRemote),
        connection.memberUpdates.listen((members) {
          if (mounted) setState(() => _members = members);
        }),
        connection.connectionState.listen((connected) {
          if (mounted) setState(() => _connected = connected);
        }),
        connection.closed.listen((_) {
          if (!mounted) return;
          showToast(context, 'The host closed this watch party.');
          Navigator.of(context).maybePop();
        }),
      ]);

      await connection.connect();
      _broadcastTimer = Timer.periodic(_broadcastInterval, (_) => _broadcast());
    } catch (err) {
      if (mounted) setState(() => _error = err);
    }
  }

  Future<void> _applyRemote(RoomState state) async {
    _guardUntil = DateTime.now().add(_echoGuard);
    await widget.onRemoteState(state);
  }

  /// Publishes our position periodically. Inside the guard window the local
  /// state is really the remote one we just applied, so it isn't re-sent.
  void _broadcast() {
    final guard = _guardUntil;
    if (guard != null && DateTime.now().isBefore(guard)) return;

    _connection?.sendState(
      playing: widget.localPlaying(),
      positionSeconds: widget.localPosition().inSeconds,
    );
  }

  String get _inviteLink {
    final base = ref.read(currentServerUrlProvider) ?? '';
    final room = _room;
    final query = {
      if (room != null) 'id': room.state.showId,
      'room': widget.code,
      if (room != null && room.state.provider.isNotEmpty)
        'provider': room.state.provider,
    };
    return '$base/watch?${Uri(queryParameters: query).query}';
  }

  Future<void> _leave() async {
    final ok = await runGuarded(
      context,
      () => ref.read(roomsApiProvider).leave(widget.code),
      successMessage: 'Left the watch party',
    );
    if (ok && mounted) Navigator.of(context).pop();
  }

  Future<void> _close() async {
    final ok = await runGuarded(
      context,
      () => ref.read(roomsApiProvider).close(widget.code),
      successMessage: 'Watch party closed',
    );
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _broadcastTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_connection?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = ref.watch(currentUserProvider);
    final isOwner = _room != null && me != null && _room!.ownerId == me.id;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.groups, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text('Watch party', style: theme.textTheme.titleMedium),
                const Spacer(),
                Icon(
                  _connected ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                  size: 18,
                  color: _connected ? theme.colorScheme.primary : theme.hintColor,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_error != null)
              ErrorState(error: _error!, scrollable: false)
            else ...[
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text('Room code', style: theme.textTheme.labelSmall),
                    const SizedBox(height: 4),
                    Text(
                      widget.code,
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(letterSpacing: 6),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: widget.code));
                        if (context.mounted) showToast(context, 'Code copied');
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy code'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => share_plus.SharePlus.instance
                          .share(share_plus.ShareParams(text: _inviteLink)),
                      icon: const Icon(Icons.ios_share, size: 18),
                      label: const Text('Invite'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('${_members.length} watching',
                    style: theme.textTheme.labelLarge),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final member in _members)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: theme.colorScheme.surface,
                          child: Text(member.initial,
                              style: theme.textTheme.labelMedium),
                        ),
                        title: Text(member.label),
                        trailing: member.isOwner
                            ? const Chip(
                                label: Text('Host'),
                                visualDensity: VisualDensity.compact)
                            : null,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (isOwner)
                FilledButton.tonalIcon(
                  onPressed: _close,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Close watch party'),
                )
              else
                FilledButton.tonalIcon(
                  onPressed: _leave,
                  icon: const Icon(Icons.logout),
                  label: const Text('Leave watch party'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
