import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/cast_providers.dart';
import 'cast_control_panel.dart';
import 'cast_sheet.dart';

/// "Something is playing on the TV" — a way back to the cast controls from a
/// screen that isn't the player.
///
/// **It renders nothing at all unless a receiver is connected *and* has media
/// loaded.** That is the whole point: casting starts on the watch screen and
/// the app then usually leaves it, so without this the only route back to
/// play/pause and seek was to reopen the exact title that was cast. A cast
/// button that is always present would be a different feature (start a cast
/// from here), which these screens have no stream to satisfy.
///
/// The panel it opens is the same one the player opens, with two differences
/// that both come from having no stream of its own: [CastControlPanel.onCastHere]
/// is null (nothing to hand the receiver from here), and `episodes` is empty,
/// so the episode *picker* is not offered. Everything else — transport,
/// volume, subtitles, audio, next/previous episode — acts on what the receiver
/// already holds and works unchanged.
class NowCastingButton extends ConsumerWidget {
  const NowCastingButton({super.key, this.compact = false});

  /// Icon only, for a tight corner. The label is worth the width where there
  /// is any: a lone cast glyph reads as "start casting" rather than as "this
  /// is casting right now".
  final bool compact;

  void _open(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // The root navigator, so the sheet covers the shell's bottom nav bar
      // instead of stopping above it: the shell puts each page in a nested
      // Navigator, and a sheet pushed there is a card floating in the page
      // with the nav still lit underneath — which reads as a panel that failed
      // to open properly rather than as a modal.
      useRootNavigator: true,
      builder: (sheetContext) => CastControlPanel(
        onChooseDevice: () {
          Navigator.of(sheetContext).pop();
          // Deliberately the *page's* context, not the sheet's: the sheet is
          // gone by the time this runs.
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useRootNavigator: true,
            builder: (_) => const CastSheet(),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No platform check: the session is the guard. Cast is Android/iOS only,
    // and on anything else the session stream is a subject seeded with null
    // that nothing ever pushes to — so this returns below without the plugin
    // being asked anything, which a `CastService.isSupported` test would only
    // duplicate (and would make this widget unrenderable in a widget test).
    final session = ref.watch(castSessionProvider).value;
    if (session == null) return const SizedBox.shrink();

    final state = ref.watch(castStateProvider).value;
    // Same fallback as the panel: the media-status stream carries changes
    // only, and this widget commonly subscribes long after the cast started.
    final status = ref.watch(castMediaStatusProvider).value ??
        ref.read(castServiceProvider).mediaStatus;
    if (!CastControlPanel.hasMedia(status, state)) return const SizedBox.shrink();

    final device = session.device?.friendlyName ?? '';
    // Whatever the receiver says it is playing, else what this app last cast:
    // the same precedence the panel's own header uses, and on Android the
    // second one is usually the only answer (see [CastService.lastLoad]).
    final fromState = state?.showTitle ?? '';
    final title = fromState.isNotEmpty
        ? fromState
        : (ref.watch(castServiceProvider).lastLoad?.displayTitle ?? '');
    final tooltip =
        device.isEmpty ? 'Casting' : 'Casting to $device — tap to control';

    if (compact) {
      return IconButton.filledTonal(
        tooltip: tooltip,
        icon: const Icon(Icons.cast_connected),
        onPressed: () => _open(context),
      );
    }

    return Tooltip(
      message: tooltip,
      child: ConstrainedBox(
        // The label is whatever is playing, which can be long; over the hero
        // artwork it has to stay a chip rather than grow into a banner.
        constraints: const BoxConstraints(maxWidth: 220),
        child: FilledButton.tonalIcon(
          icon: const Icon(Icons.cast_connected, size: 18),
          label: Text(
            title.isEmpty ? 'Casting' : title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // No `foregroundColor` here. This theme leaves `secondaryContainer`
          // unset, and it falls back to `secondary` — the accent — so a tonal
          // button is accent-filled with `onSecondary` (black) content, the
          // same look the selected nav destination has. Tinting the foreground
          // with `primary`, which is that very accent, painted the icon and
          // the label in the background colour: a solid amber pill with
          // nothing in it. The theme's progress-bar comment is the same trap.
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 14),
          ),
          onPressed: () => _open(context),
        ),
      ),
    );
  }
}
