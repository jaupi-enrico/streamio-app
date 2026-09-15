import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../shared/widgets/async_states.dart';
import '../../state/api_providers.dart';

final _myRoomsProvider = FutureProvider.autoDispose<List<Room>>((ref) async {
  return ref.watch(roomsApiProvider).mine();
});

/// `rooms.html` / `rooms.js`: join a watch party by code, or hop back into one
/// you're already in.
class RoomsScreen extends ConsumerStatefulWidget {
  const RoomsScreen({super.key});

  @override
  ConsumerState<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends ConsumerState<RoomsScreen> {
  final _code = TextEditingController();
  bool _joining = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _open(Room room) {
    final state = room.state;
    final playbackId = state.episodeId ?? state.showId;
    final query = {
      'contentType': state.contentType,
      'showId': state.showId,
      if (state.episodeLabel != null) 'episodeLabel': state.episodeLabel!,
      'room': room.code,
    };
    context.push(
        '/watch/${state.provider}/${Uri.encodeComponent(playbackId)}?${Uri(queryParameters: query).query}');
  }

  Future<void> _join() async {
    // Codes are 6 characters from an unambiguous alphabet (no O/0, I/1/L) —
    // see `generateCode()` in room.service.ts — and always uppercase.
    final code = _code.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() => _joining = true);
    try {
      final room = await ref.read(roomsApiProvider).join(code);
      if (!mounted) return;
      ref.invalidate(_myRoomsProvider);
      _open(room);
    } catch (err) {
      if (mounted) showToast(context, ErrorState.messageFor(err), isError: true);
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roomsAsync = ref.watch(_myRoomsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Watch parties')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_myRoomsProvider);
          await ref.read(_myRoomsProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Join with a code',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 6,
                    onSubmitted: (_) => _join(),
                    decoration: const InputDecoration(
                      hintText: 'AB3C9K',
                      border: OutlineInputBorder(),
                      counterText: '',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _joining ? null : _join,
                  child: _joining
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Join'),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text('Your rooms', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            roomsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => ErrorState(
                error: error,
                scrollable: false,
                onRetry: () => ref.invalidate(_myRoomsProvider),
              ),
              data: (rooms) {
                if (rooms.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'You\'re not in any watch parties. Start one from a title\'s page.',
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final room in rooms)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor:
                              Theme.of(context).colorScheme.surface,
                          child: const Icon(Icons.groups_outlined),
                        ),
                        title: Text(room.code,
                            style: const TextStyle(letterSpacing: 2)),
                        subtitle: Text(
                          [
                            room.state.episodeLabel ?? room.state.showId,
                            '${room.members.length} member'
                                '${room.members.length == 1 ? '' : 's'}',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.play_arrow),
                        onTap: () => _open(room),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
