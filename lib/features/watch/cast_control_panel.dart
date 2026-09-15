import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chrome_cast/entities.dart';
import 'package:flutter_chrome_cast/enums/player_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cast/cast_service.dart';
import '../../shared/tv.dart';
import '../../state/cast_providers.dart';

/// Controls for a running cast session: transport, tracks and episode.
///
/// The counterpart of the web sender's `#castPanel`, and it takes that
/// implementation's central lesson — **the two halves come from different
/// transports and must not be mixed**:
///
///  * *Transport* (position, playing, duration) comes from the standard Cast
///    media channel, via [castPositionProvider] and [castMediaStatusProvider].
///    It updates continuously and works even against a receiver too old to
///    speak the Streamio protocol.
///  * *Identity* (title, episode, which tracks exist) comes from the receiver's
///    `STATE` broadcast, via [castStateProvider]. It arrives every 5s and on
///    every phase change — fine for a title, far too coarse for a progress bar.
///
/// Feeding the progress bar from `STATE` would make it jump in five-second
/// steps; reading the track list from local state would go stale the moment the
/// receiver advanced an episode on its own.
///
/// **The panel owns the position it draws, not the position stream.** Three
/// things have to override the reported value or the bar is not controllable:
/// a drag in progress (the thumb must follow the finger — feeding the stream
/// straight back into `value` pins it in place and makes the bar
/// unscrubbable), an arrow-key scrub on a remote, and the second or two after
/// a seek is issued, during which the transport still reports the *old*
/// position and the bar would visibly snap back before jumping forward. All
/// three go through [_displayPosition].
class CastControlPanel extends ConsumerStatefulWidget {
  const CastControlPanel({
    super.key,
    this.episodes = const [],
    this.onCastHere,
    required this.onChooseDevice,
  });

  /// Load this screen's stream onto the connected receiver.
  ///
  /// Needed even with a session up: the receiver can be running with nothing
  /// playing — launched on the TV and sitting on its idle screen — and it is
  /// also how you move to a different title without disconnecting first.
  ///
  /// **Null when the panel is opened from somewhere with no stream of its
  /// own** — the now-casting button on the home screen, which controls what a
  /// receiver is already playing. The "Play this on the TV" affordance is then
  /// simply not offered; every other control is unaffected, since they act on
  /// what the receiver holds rather than on this screen.
  final Future<void> Function()? onCastHere;

  /// Back to the device picker, for switching receivers.
  final VoidCallback onChooseDevice;

  /// The queue as it was sent to the receiver, for labelling the episode
  /// picker. The receiver holds the same list at the same indices (see
  /// `customData.episodes`), so an index here is one it will accept.
  ///
  /// Empty is fine — the picker is simply not offered, which is also what
  /// happens for a movie.
  final List<CastEpisodeRef> episodes;

  /// Whether the receiver actually has something loaded. Public because the
  /// now-casting button ([NowCastingButton]) has to answer the same question
  /// to decide whether to appear at all, and answering it a second way is how
  /// the two end up disagreeing.
  ///
  /// Answered from the **media status**, not from `STATE`: media status rides
  /// the standard Cast channel and is therefore available whenever the session
  /// is, while `STATE` needs the custom namespace and stays null against a
  /// receiver that is fine but unreachable on it. Deciding this from `STATE`
  /// alone means a working cast reported as "nothing playing".
  ///
  /// `STATE` is consulted second, as a positive signal only — it knows about a
  /// stream being resolved, which the media status calls idle.
  static bool hasMedia(GoggleCastMediaStatus? status, CastState? state) {
    final playerState = status?.playerState;
    if (playerState == CastMediaPlayerState.playing ||
        playerState == CastMediaPlayerState.paused ||
        playerState == CastMediaPlayerState.buffering ||
        playerState == CastMediaPlayerState.loading) {
      return true;
    }
    if (status?.mediaInformation != null) return true;
    if (state == null) return false;
    return state.phase != 'IDLE' && state.phase != 'ERROR';
  }

  @override
  ConsumerState<CastControlPanel> createState() => _CastControlPanelState();
}

class _CastControlPanelState extends ConsumerState<CastControlPanel> {
  /// Where the user is dragging (or arrow-keying) to, while they are doing it.
  Duration? _scrubbing;

  /// Where the last seek was aimed, held until the transport reports a
  /// position near it. Without this the bar rubber-bands: the seek is sent,
  /// the next progress tick still carries the pre-seek position, and the thumb
  /// jumps back to where it started for as long as the receiver takes.
  Duration? _pendingSeek;
  Timer? _pendingTimeout;

  /// Whether playback has actually stopped moving.
  ///
  /// **`playerState` is a snapshot, not a live signal.** The receiver only
  /// sends a media status when something *changes*, so whichever state it
  /// happened to send last stands for as long as it likes — and if that one
  /// said `BUFFERING`, the panel goes on saying "Buffering…" over a stream
  /// that recovered seconds later and has been playing ever since. That is
  /// what "stuck on buffering" was: the position underneath it was advancing
  /// in real time the whole while. The position is the honest signal, so the
  /// word is gated on it having genuinely stopped.
  bool _stalled = false;
  Duration? _lastMovedTo;
  Timer? _stallTimer;

  /// Committing an arrow-key scrub is debounced so a held D-pad direction is
  /// one seek at the end rather than one per repeat.
  Timer? _keyScrubCommit;
  bool _seekFocused = false;

  /// Device volume, driven locally: the plugin only re-reports it in a session
  /// event, which Android emits on session lifecycle changes alone. Seeded
  /// from the session and adopted again whenever one does arrive.
  double? _volume;
  double _volumeBeforeMute = 0.6;
  bool _volumeDragging = false;

  @override
  void initState() {
    super.initState();

    _volume = ref.read(castSessionProvider).value?.currentDeviceVolume;

    ref.listenManual(castPositionProvider, (_, next) {
      final reported = next.value;
      if (reported == null) return;

      // A seek has landed once the transport reports a position near it.
      final target = _pendingSeek;
      if (target != null &&
          (reported - target).abs() <= const Duration(seconds: 3)) {
        _clearPendingSeek();
      }

      // The stream ticks every 500ms whether or not the position moved, so
      // it is the *value* changing that says playback is alive.
      if (reported == _lastMovedTo) return;
      _lastMovedTo = reported;
      if (_stalled) setState(() => _stalled = false);
      _stallTimer?.cancel();
      _stallTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _stalled = true);
      });
    });

    ref.listenManual(castSessionProvider, (previous, next) {
      final session = next.value;
      // Casting stopped from the TV, the notification, or another phone:
      // there is nothing left for this panel to control.
      if (session == null && previous?.value != null) {
        if (mounted) Navigator.of(context).maybePop();
        return;
      }
      if (session != null && !_volumeDragging) {
        final level = session.currentDeviceVolume;
        if (level != _volume) setState(() => _volume = level);
      }
    });
  }

  @override
  void dispose() {
    _pendingTimeout?.cancel();
    _keyScrubCommit?.cancel();
    _stallTimer?.cancel();
    super.dispose();
  }

  // ── Seeking ───────────────────────────────────────────────

  /// The position to draw: the scrub in progress, else the seek in flight,
  /// else what the transport says.
  Duration _displayPosition(Duration reported) =>
      _scrubbing ?? _pendingSeek ?? reported;

  void _seekTo(Duration target, Duration duration) {
    final clamped = CastService.resolveSeekTarget(
      from: target,
      offset: Duration.zero,
      duration: duration,
    );
    setState(() {
      _scrubbing = null;
      _pendingSeek = clamped;
    });
    _pendingTimeout?.cancel();
    // Failsafe: a receiver that never reports a position near the target (a
    // seek it refused, a stream that ended) must not leave the bar frozen.
    _pendingTimeout = Timer(const Duration(seconds: 8), _clearPendingSeek);
    ref.read(castServiceProvider).seekTo(clamped);
  }

  void _clearPendingSeek() {
    _pendingTimeout?.cancel();
    _pendingTimeout = null;
    if (!mounted) return;
    if (_pendingSeek != null) setState(() => _pendingSeek = null);
  }

  /// The ±10s buttons. Offset from what is *on screen*, not from the last
  /// reported tick, so two quick taps skip twenty seconds rather than ten.
  void _skip(Duration offset, Duration position, Duration duration) {
    _seekTo(
      CastService.resolveSeekTarget(
        from: _displayPosition(position),
        offset: offset,
        duration: duration,
      ),
      duration,
    );
  }

  /// Arrow-key scrubbing, for a remote. Flutter's own [Slider] key handling is
  /// deliberately not used: its step is a tenth of the range — twenty minutes
  /// on a feature film — and it fires a seek per keypress.
  KeyEventResult _onSeekKey(
    KeyEvent event,
    Duration position,
    Duration duration,
  ) {
    if (event is KeyUpEvent || duration <= Duration.zero) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      final target = _scrubbing;
      if (target == null) return KeyEventResult.ignored;
      _keyScrubCommit?.cancel();
      _seekTo(target, duration);
      return KeyEventResult.handled;
    }

    final Duration step;
    if (key == LogicalKeyboardKey.arrowRight) {
      step = const Duration(seconds: 10);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      step = const Duration(seconds: -10);
    } else {
      // Up/down fall through to traversal, which is how focus leaves the bar.
      return KeyEventResult.ignored;
    }

    final target = CastService.resolveSeekTarget(
      from: _displayPosition(position),
      offset: step,
      duration: duration,
    );
    setState(() => _scrubbing = target);

    _keyScrubCommit?.cancel();
    _keyScrubCommit = Timer(const Duration(milliseconds: 600), () {
      final pending = _scrubbing;
      if (!mounted || pending == null) return;
      _seekTo(pending, duration);
    });
    return KeyEventResult.handled;
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cast = ref.watch(castServiceProvider);
    final state = ref.watch(castStateProvider).value;
    // The stream only carries *changes*, and this panel subscribes long after
    // the cast started — so fall back to the client's current snapshot rather
    // than render an empty panel until something happens to move.
    final status = ref.watch(castMediaStatusProvider).value ?? cast.mediaStatus;

    // Position: the media channel's own clock, with STATE as the fallback for
    // the moment before the first tick arrives.
    final reported = ref.watch(castPositionProvider).value ??
        state?.position ??
        Duration.zero;
    // Duration, best source first. `STATE` is authoritative and live. The
    // media status is next — but on Android the plugin never populates
    // `mediaInformation` with a duration at all, so it is commonly null. Last
    // comes what this app itself loaded, which is the only number left when a
    // receiver isn't answering on the control channel; see
    // [CastService.lastLoad] for why that combination is ordinary rather than
    // exotic. Without it the bar had no scale: a dead thumb and `00:00` on the
    // right, over a stream that was playing perfectly well.
    final loadedLast = cast.lastLoad;
    final mediaInfo = status?.mediaInformation ?? cast.lastMediaInfo;
    final duration = state != null && state.durationSeconds > 0
        ? state.duration
        : (mediaInfo?.duration ?? loadedLast?.duration ?? Duration.zero);
    final position = _displayPosition(reported);

    // Buffering counts as playing: it is a state you leave by pausing, and
    // flipping the icon to ▶ every time the stream stalls reads as the cast
    // having stopped. With no media status at all, STATE answers instead —
    // otherwise the button reads "paused" over a stream that is playing.
    final playing = status != null
        ? (status.playerState == CastMediaPlayerState.playing ||
            status.playerState == CastMediaPlayerState.buffering)
        : (state?.playing ?? false);
    final busy = state?.isBusy ?? false;
    final loaded = CastControlPanel.hasMedia(status, state);
    // **Busy is shown, never enforced.** The receiver reports a `LOADING`
    // phase for a second or two after *every* seek, and disabling the
    // transport for it made the panel eat every other press of ±10s: tap,
    // watch the buttons grey out, tap again into a dead control, wonder why
    // nothing happened. Seeking again while the receiver is still fetching is
    // legal — CAF replaces the outstanding seek — so the only thing that
    // genuinely leaves nothing to control is nothing being loaded.
    final disabled = !loaded;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        // Scrollable because the panel grows with what the receiver offers
        // (a skip button, an audio picker, an episode row) and shrinks with
        // the viewport in landscape, where a fixed Column overflows.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, cast, state, status, mediaInfo, loadedLast),
              const SizedBox(height: 8),
              // Offered *alongside* the transport controls, never instead of
              // them. Hiding them here was a mistake worth not repeating: the
              // condition included "no STATE yet", and STATE comes from the
              // control channel — so a receiver that plays perfectly well but
              // can't be reached on the custom namespace showed no controls at
              // all, when in fact every transport control still worked.
              if (!loaded && widget.onCastHere != null) ...[
                FilledButton.icon(
                  autofocus: true,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play this on the TV'),
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await widget.onCastHere!();
                  },
                ),
                const SizedBox(height: 8),
              ],
              // The receiver's own Skip Intro/Recap/Credits action, given the
              // prominence it has on the TV rather than an icon in the tool
              // row: it is time-limited — a control you either take now or
              // lose — and it names itself.
              if (state?.skipSegment != null) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.fast_forward),
                    label: Text(state!.skipSegment!.label),
                    onPressed: cast.skipSegmentNow,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              _progress(context, position, duration, disabled),
              _transport(context, cast, state, playing, position, duration,
                  disabled, busy),
              _volumeRow(context, cast),
              const SizedBox(height: 4),
              _tools(context, cast, state, loadedLast),
            ],
          ),
        ),
      ),
    );
  }

  /// Title and episode line from the standard channel's own metadata — the
  /// same fields [CastService._metadata] populates on every LOAD, which is why
  /// they are worth reading back: they survive this app being restarted onto a
  /// cast it did not start, and they follow the receiver's own episode
  /// changes. Returns empty strings for a metadata this build doesn't know.
  static (String, String) _metadataTitle(GoogleCastMediaMetadata? metadata) {
    if (metadata is GoogleCastTvShowMediaMetadata) {
      final season = metadata.season;
      final episode = metadata.episode;
      final label = season != null && episode != null
          ? 'S${season.toString().padLeft(2, '0')}'
              'E${episode.toString().padLeft(2, '0')}'
          : '';
      return (metadata.seriesTitle ?? '', label);
    }
    if (metadata is GoogleCastMovieMediaMetadata) {
      return (metadata.title ?? '', metadata.subtitle ?? '');
    }
    if (metadata is GoogleCastGenericMediaMetadata) {
      return (metadata.title ?? '', metadata.subtitle ?? '');
    }
    return ('', '');
  }

  /// The one-line status under the title. Says what the receiver is doing when
  /// that isn't simply "playing" — a cast that sits on a black TV screen for
  /// ten seconds while a stream is re-resolved otherwise looks broken.
  String? _statusLine(CastState? state, GoggleCastMediaStatus? status) {
    switch (state?.phase) {
      case 'LOADING':
        return 'Loading…';
      case 'RESOLVING':
        return 'Finding the stream…';
      case 'RECOVERING':
        return 'Reconnecting the stream…';
      case 'UPNEXT':
        return 'Up next…';
      case 'ERROR':
        return 'The receiver reported an error.';
    }
    // Only while the position agrees. See [_stalled].
    if (status?.playerState == CastMediaPlayerState.buffering && _stalled) {
      return 'Buffering…';
    }
    return null;
  }

  Widget _header(
    BuildContext context,
    CastService cast,
    CastState? state,
    GoggleCastMediaStatus? status,
    GoogleCastMediaInformation? mediaInfo,
    CastLoad? loadedLast,
  ) {
    final device = ref.watch(castSessionProvider).value?.device?.friendlyName;
    // Three sources, most current first. `STATE` is the receiver's own answer.
    // The media metadata is next: it rides the standard channel, it is what
    // Assistant and the media notification read, and — unlike anything this
    // app remembers — it follows the receiver when *it* advances an episode.
    // What was last loaded from here comes last, and is what keeps the header
    // from reading "Casting" over a title the app knows perfectly well.
    final fromMetadata = _metadataTitle(mediaInfo?.metadata);
    final title = (state?.showTitle.isNotEmpty ?? false)
        ? state!.showTitle
        : fromMetadata.$1.isNotEmpty
            ? fromMetadata.$1
            : (loadedLast?.displayTitle.isNotEmpty ?? false)
                ? loadedLast!.displayTitle
                : 'Casting';
    final fromState = [
      if (state != null && state.episodeLabel.isNotEmpty) state.episodeLabel,
      if (state != null && CastLoad.isReadableTitle(state.episodeTitle))
        state.episodeTitle,
    ].join(' · ');
    final subtitle = fromState.isNotEmpty
        ? fromState
        : (loadedLast?.displaySubtitle.isNotEmpty ?? false)
            ? loadedLast!.displaySubtitle
            : fromMetadata.$2;
    final status0 = _statusLine(state, status);
    final theme = Theme.of(context);

    return Row(
      children: [
        const Icon(Icons.cast_connected),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              // Which TV this is going to: the panel is reachable without
              // passing through the device picker, so it is otherwise
              // impossible to tell from here.
              if (device != null && device.isNotEmpty)
                Text(
                  status0 ?? 'On $device',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                )
              else if (status0 != null)
                Text(status0, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Switch device',
          icon: const Icon(Icons.cast),
          onPressed: widget.onChooseDevice,
        ),
        IconButton(
          tooltip: 'Stop casting',
          icon: const Icon(Icons.stop_circle_outlined),
          onPressed: () async {
            await cast.disconnect();
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  Widget _progress(
    BuildContext context,
    Duration position,
    Duration duration,
    bool busy,
  ) {
    final theme = Theme.of(context);
    final max = duration.inSeconds.toDouble();
    final seekable = max > 0 && !busy;
    final value = position.inSeconds.clamp(0, duration.inSeconds).toDouble();
    // A remote has no pointer, so the bar has to be reachable and driveable
    // with the D-pad; a touch device keeps it out of the traversal order, the
    // same rule the local player's bar follows.
    final tv = isTv(context);
    final remaining = duration - position;

    final slider = Slider(
      // Still drawn at the real position while the receiver is busy — the bar
      // is disabled then, not blank: a stream being re-resolved keeps its
      // place, and zeroing it reads as playback having restarted.
      value: max > 0 ? value : 0,
      max: max > 0 ? max : 1,
      onChangeStart: seekable
          ? (seconds) =>
              setState(() => _scrubbing = Duration(seconds: seconds.round()))
          : null,
      // The value has to be taken, not discarded: driving `value` purely from
      // the position stream pins the thumb under the finger's start point and
      // makes it impossible to see — or choose — where the seek will land.
      onChanged: seekable
          ? (seconds) =>
              setState(() => _scrubbing = Duration(seconds: seconds.round()))
          : null,
      onChangeEnd: seekable
          ? (seconds) => _seekTo(Duration(seconds: seconds.round()), duration)
          : null,
      semanticFormatterCallback: (seconds) =>
          _clock(Duration(seconds: seconds.round())),
    );

    return Column(
      children: [
        Focus(
          canRequestFocus: tv && seekable,
          descendantsAreFocusable: false,
          onFocusChange: (focused) => setState(() => _seekFocused = focused),
          onKeyEvent: (_, event) => _onSeekKey(event, position, duration),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _seekFocused ? theme.colorScheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
            // Never focusable from the inside: the Slider's own arrow-key
            // handling would fight the scrubbing above, and on a touch device
            // the bar stays out of the traversal order entirely.
            child: FocusTraversalGroup(
              descendantsAreFocusable: false,
              child: slider,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _clock(position),
                style: theme.textTheme.bodySmall?.copyWith(
                  // While scrubbing, the left-hand clock *is* the readout of
                  // where the seek will land, so it is highlighted.
                  color: _scrubbing != null ? theme.colorScheme.primary : null,
                  fontWeight: _scrubbing != null ? FontWeight.w600 : null,
                ),
              ),
              Text(
                // "--:--", not "00:00": a duration nobody has reported yet is
                // unknown, and printing it as zero next to a position of 3:09
                // reads as a bug in the clock rather than as a missing number.
                duration > Duration.zero
                    ? '-${_clock(remaining.isNegative ? Duration.zero : remaining)}'
                    : '--:--',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _transport(
    BuildContext context,
    CastService cast,
    CastState? state,
    bool playing,
    Duration position,
    Duration duration,
    bool disabled,
    bool busy,
  ) {
    final index = state?.episodeIndex ?? -1;
    final isEpisode = state?.isEpisode ?? false;
    // The queue lives on the *receiver*; [episodes] is only how this panel
    // labels it. So stepping back needs the index alone and works even when
    // the panel was opened from a screen that has no queue to hand (the home
    // screen's now-casting button).
    final canPrevious = isEpisode && index > 0;
    final canNext = isEpisode;

    return FocusTraversalGroup(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isEpisode)
            IconButton(
              tooltip: 'Previous episode',
              icon: const Icon(Icons.skip_previous),
              onPressed: disabled || !canPrevious
                  ? null
                  : () => cast.playEpisodeAt(index - 1),
            ),
          IconButton(
            tooltip: 'Back 10 seconds',
            icon: const Icon(Icons.replay_10),
            onPressed: disabled
                ? null
                : () => _skip(const Duration(seconds: -10), position, duration),
          ),
          // The waiting is drawn *around* play/pause rather than in place of
          // it, so the receiver being busy never costs the user a control.
          Stack(
            alignment: Alignment.center,
            children: [
              if (busy && !disabled)
                const SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              IconButton(
                // Play/pause only claims focus when there is no "Play this on
                // the TV" above it: two autofocus nodes in one scope race, and
                // on a remote that means landing on whichever won.
                autofocus: !disabled,
                tooltip: playing ? 'Pause' : 'Play',
                iconSize: 44,
                icon: Icon(
                  playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                ),
                onPressed:
                    disabled ? null : () => cast.playOrPause(isPlaying: playing),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Forward 10 seconds',
            icon: const Icon(Icons.forward_10),
            onPressed: disabled
                ? null
                : () => _skip(const Duration(seconds: 10), position, duration),
          ),
          if (isEpisode)
            IconButton(
              tooltip: 'Next episode',
              icon: const Icon(Icons.skip_next),
              onPressed: disabled || !canNext ? null : cast.playNextNow,
            ),
        ],
      ),
    );
  }

  /// Device volume. Standard Cast, so it works against any receiver — and the
  /// TV's own remote is often not the one in the user's hand.
  ///
  /// There is no mute command in the plugin, so the speaker icon drives the
  /// level to zero and restores what it was.
  Widget _volumeRow(BuildContext context, CastService cast) {
    final level = (_volume ?? 1.0).clamp(0.0, 1.0);
    final muted = level <= 0.001;

    return Row(
      children: [
        IconButton(
          tooltip: muted ? 'Unmute' : 'Mute',
          icon: Icon(muted
              ? Icons.volume_off_outlined
              : level < 0.5
                  ? Icons.volume_down_outlined
                  : Icons.volume_up_outlined),
          onPressed: () {
            final next = muted ? _volumeBeforeMute : 0.0;
            if (!muted) _volumeBeforeMute = level > 0 ? level : 0.6;
            setState(() => _volume = next);
            cast.setVolume(next);
          },
        ),
        Expanded(
          // Same traversal rule as the seek bar, minus the D-pad handling:
          // volume is one of the few things a TV remote always has its own
          // buttons for, so it stays a touch control.
          child: FocusTraversalGroup(
            descendantsAreFocusable: false,
            child: Slider(
              value: level,
              onChangeStart: (_) => _volumeDragging = true,
              onChanged: (value) => setState(() => _volume = value),
              onChangeEnd: (value) {
                _volumeDragging = false;
                if (value > 0) _volumeBeforeMute = value;
                cast.setVolume(value);
              },
              semanticFormatterCallback: (value) =>
                  '${(value * 100).round()}% volume',
            ),
          ),
        ),
      ],
    );
  }

  Widget _tools(
    BuildContext context,
    CastService cast,
    CastState? state,
    CastLoad? loadedLast,
  ) {
    final isEpisode = state?.isEpisode ?? false;
    final episodes = _episodes(loadedLast);

    return FocusTraversalGroup(
      // A Wrap rather than a horizontal scroller: these are the panel's
      // secondary controls and there are at most five of them, so wrapping to
      // a second line keeps every one of them on screen — a scroller left the
      // last ones off the edge of a narrow phone with nothing to indicate it,
      // and a D-pad has no way to scroll a row it cannot focus into.
      child: Wrap(
        alignment: WrapAlignment.center,
        children: [
          // Which text tracks exist is only knowable from STATE, so without
          // one the picker could offer nothing but "Off" — a control that
          // can't do the thing it names. The transport controls above stay
          // regardless; they don't need the channel.
          if (state != null)
            IconButton(
              tooltip: 'Subtitles',
              isSelected: state.activeTrackId > 0,
              icon: const Icon(Icons.closed_caption_outlined),
              selectedIcon: const Icon(Icons.closed_caption),
              onPressed: () => _pickSubtitle(context, cast, state),
            ),
          // Hidden, not disabled, when the device can't enumerate the
          // manifest's audio renditions: an empty picker reads as a broken
          // control, while an absent one reads as a stream with one language.
          // See CastState.audioTracks.
          if (state?.audioTracks.isNotEmpty ?? false)
            IconButton(
              tooltip: 'Audio track',
              icon: const Icon(Icons.audiotrack_outlined),
              onPressed: () => _pickAudio(context, cast, state!),
            ),
          if (isEpisode && episodes.isNotEmpty)
            IconButton(
              tooltip: 'Episodes',
              icon: const Icon(Icons.playlist_play),
              onPressed: () => _pickEpisode(context, cast, state, episodes),
            ),
          if (isEpisode)
            IconButton(
              tooltip: (state?.autoplayNext ?? true)
                  ? 'Autoplay next: on'
                  : 'Autoplay next: off',
              isSelected: state?.autoplayNext ?? true,
              icon: const Icon(Icons.playlist_add_check_outlined),
              selectedIcon: const Icon(Icons.playlist_add_check),
              onPressed: () => cast.setAutoplay(!(state?.autoplayNext ?? true)),
            ),
        ],
      ),
    );
  }

  // ── Pickers ───────────────────────────────────────────────
  //
  // Same shape as the local player's _pickSubtitle/_pickAudioTrack in
  // watch_screen.dart: a bottom sheet of ListTiles, autofocus on the current
  // entry so a D-pad lands somewhere useful, and a check mark as the only
  // selection affordance.

  Future<void> _pickSubtitle(
    BuildContext context,
    CastService cast,
    CastState? state,
  ) async {
    final tracks = state?.subtitleTracks ?? const <CastTrack>[];
    final active = state?.activeTrackId ?? -1;

    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              autofocus: active <= 0,
              title: const Text('Off'),
              trailing: active <= 0 ? const Icon(Icons.check) : null,
              // -1 rather than 0: the receiver clears text tracks on anything
              // <= 0, but 0 is never a valid track id in the first place.
              onTap: () => Navigator.of(context).pop(-1),
            ),
            for (final track in tracks)
              ListTile(
                autofocus: track.id == active,
                title: Text(track.label),
                trailing: track.id == active ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(track.id),
              ),
          ],
        ),
      ),
    );

    if (picked != null) await cast.setSubtitle(picked);
  }

  Future<void> _pickAudio(
    BuildContext context,
    CastService cast,
    CastState state,
  ) async {
    final active = state.activeAudioTrackId;

    final picked = await showModalBottomSheet<CastTrack>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final track in state.audioTracks)
              ListTile(
                autofocus: track.id == active,
                title: Text(track.label),
                trailing: track.id == active ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(track),
              ),
          ],
        ),
      ),
    );

    // Both keys: an id the receiver just reported is the precise answer, and
    // the language lets it recover if that id has since been invalidated by an
    // episode change.
    if (picked != null) {
      await cast.setAudioTrack(trackId: picked.id, language: picked.lang);
    }
  }

  /// The queue to label the picker with: the one the opening screen handed
  /// over, else the one this app last cast. The second is what lets the
  /// home-screen button offer the picker at all — it has no queue of its own,
  /// and the receiver's `STATE` carries an index but never the list.
  List<CastEpisodeRef> _episodes(CastLoad? loadedLast) =>
      widget.episodes.isNotEmpty
          ? widget.episodes
          : (loadedLast?.episodes ?? const []);

  Future<void> _pickEpisode(
    BuildContext context,
    CastService cast,
    CastState? state,
    List<CastEpisodeRef> episodes,
  ) async {
    final current = state?.episodeIndex ?? -1;

    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (var i = 0; i < episodes.length; i++)
              ListTile(
                autofocus: i == current,
                title: Text(_episodeLabel(episodes[i])),
                subtitle: episodes[i].title.isNotEmpty
                    ? Text(episodes[i].title,
                        maxLines: 1, overflow: TextOverflow.ellipsis)
                    : null,
                trailing: i == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(i),
              ),
          ],
        ),
      ),
    );

    if (picked != null) await cast.playEpisodeAt(picked);
  }

  static String _episodeLabel(CastEpisodeRef episode) {
    final season = episode.seasonNumber;
    final number = episode.episodeNumber;
    if (season != null && number != null) {
      return 'S${season.toString().padLeft(2, '0')}'
          'E${number.toString().padLeft(2, '0')}';
    }
    if (number != null) return 'Episode $number';
    return episode.title.isNotEmpty ? episode.title : episode.id;
  }

  static String _clock(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }
}
