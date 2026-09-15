import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_chrome_cast/entities.dart';
import 'package:flutter_chrome_cast/enums/connection_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/models/models.dart';
import '../../shared/tv.dart';
import '../../shared/user_facing_error.dart';
import '../../shared/widgets/async_states.dart';
import '../../state/api_providers.dart';
import '../../state/auth_providers.dart';
import '../../state/download_providers.dart';
import '../../state/server_config_provider.dart';
import '../../state/cast_providers.dart';
import '../../core/cast/cast_service.dart'
    show CastEpisodeRef, CastPayload, CastService, CastState, CastSubtitle;
import '../details/details_providers.dart'
    show flatEpisodesProvider, nextEpisodeProvider, showDetailsProvider;
import '../social/share_sheet.dart';
import 'cast_control_panel.dart';
import 'cast_sheet.dart';
import 'room_panel.dart';
import 'watch_providers.dart';

/// The player.
///
/// Two sources feed it:
///  * **online** — `POST /api/episodes/:id/video` resolves a signed HLS URL,
///    routed through the server's proxy where the CDN demands it (see
///    [proxiedSourceUrl]);
///  * **offline** — a completed download, served by the in-app loopback
///    server that decrypts segments on the fly.
///
/// media_kit (libmpv) rather than video_player: it forwards custom HTTP
/// headers to *every* child request of an HLS playlist, which these CDNs
/// require, and it handles demuxed audio/video renditions.
class WatchScreen extends ConsumerStatefulWidget {
  const WatchScreen({
    super.key,
    required this.provider,
    required this.id,
    this.contentType,
    this.showId,
    this.title,
    this.episodeLabel,
    this.roomCode,
    this.downloadId,
    this.startSeconds,
  });

  final String provider;

  /// The playable id: an episode id, or a movie id when [contentType] is
  /// "movie".
  final String id;
  final String? contentType;

  /// The parent title's id, so history is recorded against the show rather
  /// than the episode.
  final String? showId;
  final String? title;
  final String? episodeLabel;
  final String? roomCode;

  /// Set when opened from the Downloads screen: play locally, no network.
  final String? downloadId;
  final int? startSeconds;

  @override
  ConsumerState<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends ConsumerState<WatchScreen> {
  static const _progressInterval = Duration(seconds: 10);

  /// Slower than [_progressInterval]: a cast keeps playing with the app in the
  /// background, and this is the cadence the web sender settled on for the
  /// same reason.
  static const _castProgressInterval = Duration(seconds: 30);

  /// How long before the end the "next episode" prompt appears — matches
  /// `watch.js`'s `NEXT_EP_THRESHOLD`.
  static const _nextEpisodeThreshold = Duration(seconds: 20);

  /// Socket inactivity budget handed to libmpv, in seconds.
  ///
  /// media_kit's own default is **5**, which is far too tight for this app's
  /// topology and is the direct cause of mid-playback
  /// `tcp: ffurl_read returned 0xdfb9b0bb` (that hex is FFmpeg's `AVERROR_EOF`
  /// — the connection ended before the body did). Every fragment travels
  /// device → proxy hops → server → upstream CDN, and
  /// `/api/cast-proxy` cannot emit a byte until the CDN has answered *it*: the
  /// server allows itself 25s just to reach first byte upstream. A client that
  /// gives up after 5s of silence therefore tears down connections the server
  /// was still legitimately servicing.
  ///
  /// 30s is the same budget the web player gives hls.js
  /// (`fragLoadPolicy.maxTimeToFirstByteMs` in `../web/public/scripts/watch.js`)
  /// and sits above the proxy's 25s abort, so a genuinely dead upstream
  /// arrives as the proxy's own 504 rather than as a client-side timeout.
  static const _networkTimeoutSeconds = 30;

  /// How long a reported stream error is given to resolve itself before the
  /// stream is re-resolved.
  ///
  /// libmpv recovers from most of these on its own (it reopens the connection
  /// and refetches the segment — `demuxer-lavf-o` already carries
  /// `seg_max_retry=5`), so the error log arrives while playback is about to
  /// continue normally. Acting on the log itself is what turned a hiccup into
  /// a dead player.
  static const _stallGrace = Duration(seconds: 6);

  /// Shorter grace when nothing has played yet: there is no playback to
  /// protect, so a stream that fails to open should not sit on a spinner.
  static const _openStallGrace = Duration(seconds: 2);

  /// Matches `MAX_STREAM_RETRIES` in `../web/public/scripts/watch.js`.
  static const _maxRecoveryAttempts = 5;

  /// Uninterrupted playback after which the recovery budget is considered
  /// spent-and-refilled. Without it a stream that plays a second between each
  /// failure would reset the counter every time and retry forever.
  static const _recoveryBudgetResetAfter = Duration(seconds: 60);

  late final Player _player = Player();

  /// Set once a decoder error has forced this session off the zero-copy
  /// Android output (see [_zeroCopyVideo]). Static so a box that can't use it
  /// pays the one failed open once, not on every title.
  static bool _zeroCopyVideoUnsupported = false;

  /// Whether to render through libmpv's `mediacodec_embed` output.
  ///
  /// media_kit's Android default is `--vo=gpu --hwdec=auto-safe`, which
  /// resolves to `mediacodec-copy`: MediaCodec decodes in hardware, then every
  /// frame is copied back into CPU memory and re-uploaded to the GPU as a
  /// texture. A phone absorbs that. A TV box — a quad-A53 with shared memory
  /// bandwidth — does not: at 1080p it's ~3 MB per frame down and back up
  /// again, the video pipeline falls behind while the audio output (which
  /// costs nothing to keep fed) plays on, and the picture ends up both stuttery
  /// and progressively out of sync with the sound. It only shows up on the
  /// higher variants because the copy cost scales with resolution — which is
  /// why "auto" and "high" break and a lower quality doesn't.
  ///
  /// `mediacodec_embed` hands MediaCodec the output surface directly, so
  /// decoded frames never leave the GPU. It is the narrower path (see
  /// [_recoverFromVideoDecoderError]), so it is asked for only where the copy
  /// path measurably can't cope.
  late final bool _zeroCopyVideo =
      Platform.isAndroid && TvPlatform.isTvDevice && !_zeroCopyVideoUnsupported;

  /// Hardware video output, on every platform.
  ///
  /// Linux used to be excluded here (`!Platform.isLinux`): on the NVIDIA
  /// proprietary driver the EGL texture path produced a solid blue video
  /// surface instead of decoded frames, and software rendering was the
  /// documented media_kit workaround. That turned out to be a symptom of the
  /// *engine's* renderer, not of media_kit — the Linux default had become
  /// Impeller, which on that driver also segfaults the rasterizer thread
  /// outright. `linux/runner/main.cc` now pins the engine to Skia, and with
  /// that in place media_kit reports "H/W rendering with isolated EGL
  /// context" and the picture is correct.
  ///
  /// This matters for more than the blue frames: forcing software rendering
  /// meant decoding and blitting every frame on the CPU, which is what made
  /// Linux playback stutter. Verified on an RTX 3070 (driver 610.57).
  late final VideoController _controller = VideoController(
    _player,
    configuration: VideoControllerConfiguration(
      enableHardwareAcceleration: true,
      // Both or neither: mediacodec_embed can only draw frames the hardware
      // decoder put in its surface, so it has to be paired with the direct
      // (non-copying) hwdec. `null` leaves media_kit's own defaults in place.
      vo: _zeroCopyVideo ? 'mediacodec_embed' : null,
      hwdec: _zeroCopyVideo ? 'mediacodec' : null,
    ),
  );

  final _subscriptions = <StreamSubscription<dynamic>>[];

  bool _loading = true;
  Object? _error;

  List<VideoServer> _servers = const [];
  int _serverIndex = 0;
  String? _tempManifestPath;

  /// The un-proxied stream URL from the last resolve. Cast needs the raw one
  /// so it can wrap it in the *absolute* proxy base the receiver requires,
  /// which differs from the root-relative one used for local playback.
  String? _rawStreamUrl;
  PlaybackSource? _lastSource;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _scrubbing = false;

  Timer? _progressTimer;
  int _lastSavedSeconds = -1;

  /// Progress written from the receiver's `STATE`, tracked separately from
  /// [_lastSavedSeconds]: while casting, the local player is paused and its
  /// position is frozen, so the two counters describe different playbacks and
  /// must not dedupe against each other.
  int _lastCastSavedSeconds = -1;
  DateTime? _lastCastSaveAt;

  /// The session this screen last handed a stream to, when the platform gives
  /// one. Used only to notice a switch to a *different* receiver.
  String? _castLoadedSessionId;

  /// Whether the connected session has already been given this screen's
  /// stream. Reset when the session goes away. This — not the session id — is
  /// what stops [_wireCastAutoLoad] re-issuing a LOAD on every state change,
  /// since the id can be null for a whole session and the receiver honours a
  /// duplicate LOAD by restarting the stream from the beginning.
  bool _castHandedOff = false;

  /// Held across [_castCurrentStream]'s awaits. The session stream can emit
  /// several times while a load is still building its payload, and a second
  /// LOAD is not harmless — the receiver honours it by restarting the stream.
  bool _castLoading = false;

  /// Guards [_saveProgress] against a stomp: mpv can report a stray near-zero
  /// position for a moment after `open()` while the resume seek is still
  /// converging (see [_confirmResumePosition]). Saving during that window
  /// would overwrite the real resume point with 0. Starts true when there's
  /// no resume target to wait for.
  bool _resumeConfirmed = true;

  /// Set once the user (or the watch party) picks a position by hand, so the
  /// resume retry loop stops forcing them back to the stored one.
  bool _userSeeked = false;

  bool _controlsVisible = true;
  Timer? _hideControlsTimer;

  /// Whether this is a D-pad-only device, resolved in
  /// [didChangeDependencies] because several of the key handlers below need
  /// the answer outside a build.
  bool _tv = false;

  /// Holds focus whenever the overlay is hidden — with the controls
  /// focus-excluded there is nothing else on this screen that can, and a
  /// screen with no focused node swallows the first D-pad press.
  final _screenFocus = FocusNode(debugLabel: 'watch screen');

  /// Focus is put back here by hand every time the overlay is summoned:
  /// `autofocus` only fires when a node is first created, and these nodes
  /// outlive each hide/show cycle.
  final _playPauseFocus = FocusNode(debugLabel: 'play/pause');

  /// Set by the prompt's cancel button. Once cancelled, autoplay stays off
  /// for the rest of this screen's life (a new episode is a new
  /// [WatchScreen], so it resets naturally) — same session-scoped opt-out as
  /// `watch.js`'s `autoplayNextEnabled`.
  bool _autoplayNextCancelled = false;

  /// Skip Intro/Recap/Credits/Preview segments for the title now playing
  /// (TheIntroDB), fetched once in [initState]. Null both before the lookup
  /// resolves and when nothing was found — either way the button just never
  /// appears, the same fail-silent contract the server-side lookup has.
  IntroDbMedia? _introSegments;

  /// Bumped on every [_load]. Lets a stray [_confirmResumePosition] from a
  /// superseded load (server switch, retry) recognize it's stale and stop.
  int _loadGeneration = 0;

  // ── Stream recovery ──────────────────────────────────────
  //
  // See [_handleStreamError]. The web player's counterparts are
  // `streamRetryCount` / `retryCurrentStream()` in
  // `../web/public/scripts/watch.js`.

  /// Armed by a stream error, disarmed by playback carrying on regardless.
  /// Non-null means an error is being watched and further ones are ignored —
  /// mpv emits these in bursts, and re-arming per error would push the
  /// decision back indefinitely.
  Timer? _stallWatchdog;

  /// The last error libmpv reported, kept so it can be shown if recovery
  /// eventually gives up. Showing it *immediately* is the bug this replaces.
  String? _lastStreamError;

  /// True between noticing trouble and either recovering or giving up. Drives
  /// the "Reconnecting…" overlay.
  bool _reconnecting = false;

  /// Guards against a second recovery starting while one is in flight.
  bool _recovering = false;

  int _recoveryAttempts = 0;
  DateTime? _lastRecoveryAt;

  /// Applied once, before the first `open()`. `network-timeout` is read when a
  /// connection is opened, so it must be in place by then; awaiting the same
  /// future on every later [_load] costs nothing.
  late final Future<void> _networkTuning = _tuneNetworkOptions();

  bool get _isOffline => widget.downloadId != null;
  String get _contentType => widget.contentType ?? 'episode';
  String get _historyShowId => widget.showId ?? widget.id;
  String? get _historyEpisodeId => _contentType == 'episode' ? widget.id : null;

  @override
  void initState() {
    super.initState();
    // Playback is a lean-back experience; the UI mode is restored in
    // dispose() so the rest of the app is unaffected.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _wirePlayerStreams();
    _wireCastAutoLoad();
    _wireCastProgress();
    _load();
    // Independent of _load(): segments are per-episode, not per-server, so a
    // server retry (_pickServer) must not re-fetch them. Fire-and-forget —
    // must never delay stream start.
    unawaited(_loadIntroSegments());
    _resetHideControlsTimer();
  }

  /// Casts the current stream as soon as a session goes active.
  ///
  /// The web sender's `onCastSessionStarted` does exactly this, for
  /// `SESSION_STARTED` *and* `SESSION_RESUMED`, and the reason is the same:
  /// connecting to a device and giving it something to play are one intent,
  /// and a session can become active without this app initiating it — resumed
  /// from the media notification, or joined because the receiver is already
  /// running on the TV. Waiting for a second, manual step there means a
  /// receiver sitting on its idle screen with no way to be handed a stream.
  ///
  /// **Two things had to be true for that to hold and only one of them was.**
  /// A session very often exists *before* this screen does — cast from the
  /// home screen, or simply open the next episode while the TV is already
  /// playing — and a listener wired to `castSessionProvider` only sees it
  /// *change*, so nothing ever fired: every episode after the first had to be
  /// pushed by hand from "Play this on the TV". Hence `fireImmediately`. And
  /// even then the session can be up while the stream is still resolving,
  /// which leaves [_maybeAutoCast] with nothing to send — so [_load] calls it
  /// again once there is.
  void _wireCastAutoLoad() {
    if (_isOffline || !CastService.isSupported) return;
    ref.listenManual(
      castSessionProvider,
      (_, next) => _onCastSession(next.value),
      fireImmediately: true,
    );
  }

  /// Re-runs the hand-off decision against the session as it stands, for the
  /// callers that aren't the session stream itself.
  void _maybeAutoCast() {
    if (_isOffline || !CastService.isSupported) return;
    _onCastSession(ref.read(castSessionProvider).value);
  }

  void _onCastSession(GoogleCastSession? session) {
    if (session == null ||
        session.connectionState == GoogleCastConnectState.disconnected) {
      // Casting again after disconnecting is a new session, so arm the
      // hand-off again rather than treating the next one as already loaded.
      _castHandedOff = false;
      _castLoadedSessionId = null;
      _castLoading = false;
      return;
    }

    // The stream only goes anywhere once the session is actually up; this
    // stream also reports `connecting`.
    if (session.connectionState != GoogleCastConnectState.connected) return;

    // A *different* session id is a different receiver, so the stream has to
    // be handed over again. The id is only ever compared when both sides
    // have one: a session can report a null id mid-handshake, and this must
    // not turn into "already loaded".
    final id = session.sessionID;
    if (id != null && _castLoadedSessionId != null &&
        id != _castLoadedSessionId) {
      _castHandedOff = false;
    }

    // The guard is a flag rather than the id itself, because the id may be
    // null on this platform for the whole session — in which case an id
    // comparison would let every state change re-issue the LOAD, and the
    // receiver honours a duplicate LOAD by restarting the stream.
    if (_castHandedOff || _castLoading) return;
    // Nothing resolved yet. _load() calls back here the moment there is.
    if (_rawStreamUrl == null) return;

    _castCurrentStream();
  }

  /// Keeps watch history moving while a cast is running.
  ///
  /// The local player is paused for the whole cast (see [_openCastSheet]), so
  /// `_position` is frozen and [_saveProgress] has nothing to record — history
  /// simply stopped at the moment of casting. The receiver's `STATE` broadcast
  /// is the only position that means anything from here on, and it also
  /// carries the episode the receiver is *actually* on, which is not
  /// necessarily the one that was cast: it advances episodes by itself.
  void _wireCastProgress() {
    if (_isOffline || !CastService.isSupported) return;
    ref.listenManual(castStateProvider, (_, next) {
      final state = next.value;
      if (state != null) _saveCastProgress(state);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tv = isTv(context);
  }

  void _wirePlayerStreams() {
    _subscriptions.addAll([
      _player.stream.position.listen((position) {
        if (!mounted || _scrubbing) return;
        // libmpv observes `time-pos` unthrottled, so this fires once per
        // *decoded frame* — 25 to 60 times a second. Rebuilding the whole
        // screen (the overlay, its slider, the next-episode lookup) that often
        // costs nothing on a phone and is a meaningful share of a TV box's
        // single-threaded UI budget, competing with the decode it is trying to
        // keep up with. Everything the position drives — the timestamps, the
        // progress bar, the countdown — has one-second resolution, so keep the
        // field exact and only rebuild when the displayed value moves.
        final changed = position.inSeconds != _position.inSeconds;
        _position = position;
        if (changed) setState(() {});
      }),
      _player.stream.duration.listen((duration) {
        if (!mounted) return;
        setState(() => _duration = duration);
      }),
      _player.stream.playing.listen((playing) {
        if (!mounted) return;
        setState(() => _playing = playing);
        // Nothing to auto-hide while paused — show the controls the user just
        // asked for by pausing, and (on a remote) put focus back on the
        // play/pause button so the next OK press resumes.
        if (playing) {
          _resetHideControlsTimer();
        } else {
          _showControls();
        }
        // Pausing is the save point users expect to survive a force-quit.
        if (!playing) unawaited(_saveProgress());
      }),
      _player.stream.completed.listen((completed) {
        if (completed) unawaited(_onCompleted());
      }),
      _player.stream.error.listen((message) {
        if (!mounted || message.isEmpty) return;
        if (_recoverFromVideoDecoderError(message)) return;
        _handleStreamError(message);
      }),
    ]);
  }

  /// Raises libmpv's network budgets off media_kit's defaults.
  ///
  /// media_kit sets `network-timeout: 5` for every player it creates, which is
  /// a general-purpose default and wrong for a proxied, tunnelled stream —
  /// see [_networkTimeoutSeconds].
  ///
  /// Only `network-timeout` is set here, deliberately. The obvious companion
  /// would be FFmpeg's `reconnect`/`reconnect_streamed` via
  /// `demuxer-lavf-o`, but that is both unsafe and useless in this position:
  /// unsafe because the property is a single string that media_kit already
  /// populates (`protocol_whitelist` among others) and rewriting it would drop
  /// whatever this version put there, and useless because libavformat's HLS
  /// demuxer forwards only a fixed whitelist of options to the connections it
  /// opens for child playlists and segments — `reconnect` is not on it, and
  /// segment fetches are exactly where these errors happen. `rw_timeout`,
  /// which is what `network-timeout` becomes, *is* on it. Recovery from a
  /// connection that genuinely died is [_handleStreamError]'s job instead.
  Future<void> _tuneNetworkOptions() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.setProperty(
          'network-timeout', '$_networkTimeoutSeconds');
    } catch (err) {
      // A player that won't take the property still plays; it just keeps the
      // tighter default. Never a reason to fail the playback.
      debugPrint('[watch] could not raise network-timeout: $err');
    }
  }

  /// Decides whether a libmpv error is worth ending the playback over.
  ///
  /// It usually is not. media_kit forwards *any* ffmpeg log line at error
  /// level whose text starts with `tcp:` (see `errorController` in its
  /// `native/player/real.dart`), and mpv emits those routinely mid-stream:
  /// a keep-alive connection the CDN closed between segments, a read cut
  /// short, a fetch that outran the socket timeout. The canonical one is
  /// `tcp: ffurl_read returned 0xdfb9b0bb` — `AVERROR_EOF`, i.e. "the
  /// connection ended". libmpv reopens and carries on; the screen used to be
  /// replaced by an error the moment the *log* arrived, which is what made
  /// playback die at random points in a title that was otherwise fine.
  ///
  /// So the log is not the signal — a stalled playhead is. Give the player
  /// [_stallGrace] to keep going by itself; if it does, the error was noise.
  /// If it does not, re-resolve and resume where the viewer was, which also
  /// covers the failure the retry-in-place can never fix: these URLs are
  /// signed and expire in minutes, so a long enough title (or a long enough
  /// pause) outlives its own stream and every segment request starts failing.
  void _handleStreamError(String message) {
    _lastStreamError = message;
    debugPrint('[watch] stream error: $message');

    // Offline playback is served by this app's own loopback server, so there
    // is no network to recover from and re-resolving means nothing: a failure
    // there is a real one (a missing or undecryptable segment).
    if (_isOffline) {
      setState(() {
        _error = PlaybackFailure(message);
        _loading = false;
      });
      return;
    }

    // Already watching, or already acting. mpv reports these in bursts.
    if (_stallWatchdog != null || _recovering) return;

    setState(() => _reconnecting = true);

    // Nothing has played yet, so there is no playback to protect and no
    // reason to sit on a spinner for the full grace period.
    final grace = _duration == Duration.zero ? _openStallGrace : _stallGrace;
    final positionAtError = _position;

    _stallWatchdog = Timer(grace, () {
      _stallWatchdog = null;
      if (!mounted) return;

      // Paused: the playhead is standing still because the viewer stopped it,
      // not because the stream is broken. If the stream really is dead, the
      // attempt to resume produces a fresh error and we start over from there.
      if (!_playing) {
        setState(() => _reconnecting = false);
        return;
      }

      if (_position > positionAtError + const Duration(milliseconds: 500)) {
        // It kept playing. The log was noise.
        setState(() => _reconnecting = false);
        return;
      }

      unawaited(_recoverStream());
    });
  }

  /// Re-resolves the current server and resumes at the current position.
  ///
  /// Mirrors `retryCurrentStream()` in `../web/public/scripts/watch.js`, down
  /// to the backoff and the attempt cap, with two differences the app can
  /// afford: the resume point is the live playhead rather than the progress
  /// row the server last stored (which lags by up to [_progressInterval]), and
  /// the already-fetched server list is reused so a retry costs one request
  /// rather than two.
  Future<void> _recoverStream() async {
    if (_recovering || !mounted) return;

    // Playback that ran for a good while before failing again is not the same
    // incident, so it gets its own budget rather than counting against the
    // previous one.
    final lastRecovery = _lastRecoveryAt;
    if (lastRecovery != null &&
        DateTime.now().difference(lastRecovery) > _recoveryBudgetResetAfter) {
      _recoveryAttempts = 0;
    }

    if (_recoveryAttempts >= _maxRecoveryAttempts) {
      setState(() {
        _reconnecting = false;
        _error = PlaybackFailure(_lastStreamError ??
            'The stream stopped responding and could not be restarted.');
        _loading = false;
      });
      return;
    }

    _recovering = true;
    _recoveryAttempts++;
    _lastRecoveryAt = DateTime.now();
    final resumeFrom = _position;

    try {
      // Same backoff curve as the web player: 1s, 2s, 4s, 8s, 8s.
      final delayMs = 1000 * (1 << (_recoveryAttempts - 1));
      await Future<void>.delayed(
          Duration(milliseconds: delayMs > 8000 ? 8000 : delayMs));
      if (!mounted) return;

      debugPrint('[watch] recovery attempt $_recoveryAttempts '
          'from $resumeFrom');
      // `fresh: true` is the point of the retry: without it the server's
      // resolve cache hands back the same expired URL and every attempt fails
      // identically.
      await _load(
        serverIndex: _serverIndex,
        resumeFrom: resumeFrom,
        fresh: true,
      );
    } finally {
      _recovering = false;
      if (mounted) setState(() => _reconnecting = false);
    }
  }

  /// Drops this player off the zero-copy output when the device turns out not
  /// to support it for the stream in hand, instead of failing the playback.
  ///
  /// `mediacodec_embed` can only present frames MediaCodec itself put in the
  /// surface, so a stream the hardware decoder refuses — an unusual profile,
  /// 10-bit HEVC on an older box — leaves it with nothing to draw: mpv falls
  /// back to decoding in software and the picture never appears while the
  /// audio plays on. libmpv reports the refusal from its decoder (`vd`), which
  /// is the cue to put this player back on the (universally compatible, just
  /// slower) copying path. The static flag means the next title skips the
  /// failed attempt entirely.
  ///
  /// Returns whether the error was handled and should be kept off the screen.
  bool _recoverFromVideoDecoderError(String message) {
    if (!_zeroCopyVideo || _zeroCopyVideoUnsupported) return false;

    final text = message.toLowerCase();
    const decoderFailures = [
      'could not open codec',
      'failed to initialize a decoder',
      'hardware decoding failed',
    ];
    if (!decoderFailures.any(text.contains)) return false;

    debugPrint('[video] mediacodec_embed refused the stream ($message); '
        'falling back to the copying output');
    _zeroCopyVideoUnsupported = true;
    unawaited(_useCopyingVideoOutput());
    return true;
  }

  /// mpv takes both of these at runtime, so the switch costs a decoder reinit
  /// rather than a re-resolve of the (signed, expiring) stream URL.
  Future<void> _useCopyingVideoOutput() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    // The decoder goes first: the new output must never be handed a frame the
    // old hwdec produced.
    await platform.setProperty('hwdec', 'mediacodec-copy');
    await platform.setProperty('vo', 'gpu');
    // Set explicitly because leaving mediacodec_embed leaves --vid needing
    // reinitialisation — media_kit's own surface listener does the same.
    await platform.setProperty('vid', 'auto');
    if (!mounted) return;
    // Nothing above reopens the video chain on its own; a seek to where we
    // already are does, without moving the user.
    await _player.seek(_player.state.position);
  }

  @override
  void dispose() {
    // Fire-and-forget: the widget is going away, but the last position is
    // worth persisting.
    unawaited(_saveProgress());
    _progressTimer?.cancel();
    _hideControlsTimer?.cancel();
    _stallWatchdog?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _player.dispose();
    _screenFocus.dispose();
    _playPauseFocus.dispose();
    if (_tempManifestPath != null) {
      File(_tempManifestPath!).delete().ignore();
    }
    if (_isOffline) unawaited(ref.read(localMediaServerProvider).stop());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ── Loading ───────────────────────────────────────────────

  /// [resumeFrom] overrides the stored progress — used by [_recoverStream],
  /// which knows the live playhead and must not send the viewer back to the
  /// last ten-second checkpoint every time a stream is restarted.
  Future<void> _load(
      {int? serverIndex, Duration? resumeFrom, bool fresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final generation = ++_loadGeneration;

    // A superseded load's watchdog must not re-resolve on top of this one.
    _stallWatchdog?.cancel();
    _stallWatchdog = null;
    // Any load that isn't itself a recovery — the first one, a server switch,
    // the viewer tapping Retry — is a new intent and starts the budget over.
    if (!fresh) {
      _recoveryAttempts = 0;
      _lastRecoveryAt = null;
    }

    try {
      await _networkTuning;
      final start = resumeFrom != null
          ? (resumeFrom > const Duration(seconds: 5) ? resumeFrom : null)
          : await _resolveStartPosition();
      final media = _isOffline
          ? await _offlineMedia(start: start)
          : await _onlineMedia(
              serverIndex: serverIndex ?? _serverIndex,
              start: start,
              fresh: fresh);

      _resumeConfirmed = start == null;
      _userSeeked = false;
      await _player.open(media);
      if (mounted) setState(() => _loading = false);
      _startProgressTimer();
      unawaited(_confirmResumePosition(start, generation));
      // A receiver connected before or during this resolve has been waiting
      // for something to play: the session listener already ran and found
      // `_rawStreamUrl` null. It is set now.
      _maybeAutoCast();
    } catch (err) {
      if (mounted) {
        setState(() {
          _error = err;
          _loading = false;
        });
      }
    }
  }

  /// mpv applies [Media.start] via an `on_load` hook, but for network HLS the
  /// demuxer is often not genuinely seekable until well after that hook runs
  /// — the manifest parses fast, but mpv can still snap back to 0 once real
  /// playback catches up. Poll for a few seconds and force a seek if the
  /// position never lands near the target.
  Future<void> _confirmResumePosition(Duration? start, int generation) async {
    debugPrint('[resume] target=$start');
    if (start == null) return;

    // Neither `playing` (flips true the instant open() is called, well
    // before mpv is actually delivering frames) nor a single read of
    // `buffering` (can reflect a stale snapshot from the previous media) is
    // a trustworthy one-shot readiness signal — and neither is one on-target
    // position reading. Right after open() mpv reports back the `Media.start`
    // it was handed, which is bookkeeping, not a decoded frame: the position
    // shows the resume point, then snaps to 0 the moment the first image
    // actually arrives. Stopping at that first reading is what made the
    // resume look like it "took, then restarted from 0:00".
    //
    // So the resume counts as landed only once the position has held at or
    // past the target across consecutive samples *while advancing on its
    // own*, which is something only real playback does. Re-issuing the seek
    // meanwhile is harmless — a no-op once already on target.
    //
    // Until this settles, [_saveProgress] must not trust `_position`: saving
    // one of those stray near-zero readings would overwrite the real resume
    // point with 0 (e.g. the user pausing or backing out right after
    // opening).
    const tolerance = Duration(seconds: 5);
    var settled = 0;
    Duration? previous;

    try {
      for (var attempt = 0; attempt < 80; attempt++) {
        await Future.delayed(const Duration(milliseconds: 250));
        if (!mounted || generation != _loadGeneration) return;
        // A manual seek means the user has chosen their own position; stop
        // dragging them back to the stored one.
        if (_userSeeked) return;

        final position = _player.state.position;
        final last = previous;
        final advanced = last != null && position > last;
        previous = position;

        // Being *past* the target is playback progressing, not a miss.
        if (position >= start - tolerance) {
          if (advanced && _player.state.playing) settled++;
          if (settled >= 3) {
            debugPrint('[resume] settled at $position');
            return;
          }
          continue;
        }

        debugPrint(
            '[resume] attempt=$attempt fell back to $position, re-seeking');
        settled = 0;
        await _player.seek(start);
      }
    } finally {
      if (mounted && generation == _loadGeneration) _resumeConfirmed = true;
    }
  }

  Future<Media> _offlineMedia({Duration? start}) async {
    final url =
        await ref.read(localMediaServerProvider).serve(widget.downloadId!);
    return Media(url, start: start);
  }

  Future<Media> _onlineMedia(
      {required int serverIndex, Duration? start, bool fresh = false}) async {
    final result = await resolvePlayback(
      ref.read(contentApiProvider),
      widget.provider,
      widget.id,
      contentType: _contentType,
      knownServers: _servers.isEmpty ? null : _servers,
      serverIndex: serverIndex,
      fresh: fresh,
    );

    _servers = result.servers;
    _serverIndex = result.serverIndex;

    final source = result.source;
    var uri = source.url;
    _rawStreamUrl = source.url.isEmpty ? null : source.url;
    // Kept for the Chromecast payload: its subtitle list and stream type are
    // resolved here and needed later, when the user opens the cast sheet.
    _lastSource = source;

    // Some extractors return the manifest itself rather than a URL. libmpv
    // can't open a `data:` URI, so it goes to a temp file — the same problem
    // the web player solves with a Blob URL.
    if (source.inlineManifest != null && source.inlineManifest!.isNotEmpty) {
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/${const Uuid().v4()}.m3u8';
      await File(path).writeAsString(source.inlineManifest!);
      _tempManifestPath = path;
      uri = path;
    } else {
      final baseUrl = ref.read(currentServerUrlProvider);
      if (baseUrl != null) {
        uri = proxiedSourceUrl(uri, baseUrl, headers: source.headers);
      }
    }

    return Media(uri, httpHeaders: source.headers, start: start);
  }

  /// Resume point: the `t=` the caller passed (from Continue Watching or a
  /// download), otherwise whatever the server has stored.
  ///
  /// Resolved before `_player.open()` so it can be passed as [Media.start] —
  /// a post-open `Player.seek()` races mpv opening the HLS source and is
  /// often dropped, which looked like the stream "starting over".
  Future<Duration?> _resolveStartPosition() async {
    var start = widget.startSeconds ?? 0;

    if (start == 0 && !_isOffline && ref.read(isSignedInProvider)) {
      try {
        final progress = await ref.read(accountApiProvider).progress(
              provider: widget.provider,
              showId: _historyShowId,
              episodeId: _historyEpisodeId,
            );
        if (progress != null && !progress.completed) {
          start = progress.progressSeconds;
        }
      } catch (_) {
        // No resume point isn't worth interrupting playback for.
      }
    }

    // Don't "resume" someone into the last seconds of a title.
    final result = start > 5 ? Duration(seconds: start) : null;
    debugPrint('[resume] resolved start=$result (raw start=$start)');
    return result;
  }

  // ── Controls visibility ──────────────────────────────────

  /// Auto-hides the overlay after inactivity, matching every other video
  /// player. `Video(controls: NoVideoControls)` opts out of media_kit's own
  /// chrome (and its built-in auto-hide) so this app's replacement overlay
  /// has to reimplement it.
  void _resetHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if (!_playing) return; // don't hide while paused; nothing to look at.
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      _hideControls();
    });
  }

  void _hideControls() {
    _hideControlsTimer?.cancel();
    setState(() => _controlsVisible = false);
    // The overlay is about to be focus-excluded (see _buildScaffold). Take
    // focus back deliberately rather than letting the focus manager drop it
    // on the floor — an unfocused screen ignores the next D-pad press.
    _screenFocus.requestFocus();
  }

  /// Summons the overlay and, on a remote, puts focus somewhere useful.
  void _showControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _resetHideControlsTimer();
    if (!_tv) return;
    // One frame later: the buttons are only un-excluded once this setState
    // has been laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controlsVisible) _playPauseFocus.requestFocus();
    });
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideControls();
    } else {
      _showControls();
    }
  }

  /// Shared by the skip buttons and the keyboard shortcuts below, so both
  /// skip by the same 10s and both count as a manual seek.
  void _seekBy(Duration offset) {
    _userSeeked = true;
    _player.seek(_position + offset);
    // A keyboard skip should surface the controls the same way a tap does,
    // even if the shortcut fired while they were hidden.
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _resetHideControlsTimer();
  }

  // ── Progress ──────────────────────────────────────────────

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(_progressInterval, (_) => _saveProgress());
  }

  Future<void> _saveProgress({bool completed = false}) async {
    // See _confirmResumePosition: `_position` isn't trustworthy until the
    // resume seek has landed, and saving early would stomp the real resume
    // point with a stray near-zero reading.
    if (!_resumeConfirmed) return;

    final seconds = _position.inSeconds;
    if (seconds <= 0) return;
    if (!completed && seconds == _lastSavedSeconds) return;
    _lastSavedSeconds = seconds;

    // Offline playback keeps progress on the local row and flags it for the
    // next sync, so an airplane-mode session isn't lost.
    if (_isOffline) {
      await ref.read(appDatabaseProvider).updateDownload(
            widget.downloadId!,
            DownloadsCompanion(
              progressSeconds: Value(seconds),
              progressSynced: const Value(false),
            ),
          );
      return;
    }

    if (!ref.read(isSignedInProvider)) return;

    try {
      await ref.read(accountApiProvider).saveProgress(
            provider: widget.provider,
            showId: _historyShowId,
            episodeId: _historyEpisodeId,
            episodeLabel: widget.episodeLabel,
            progressSeconds: seconds,
            durationSeconds:
                _duration.inSeconds > 0 ? _duration.inSeconds : null,
            completed: completed,
          );
    } catch (_) {
      // Progress is best-effort; a failed save must not interrupt playback.
    }
  }

  /// Writes history from a receiver `STATE`. Throttled to
  /// [_castProgressInterval] rather than fired on every broadcast: `STATE`
  /// arrives every 5s and history is not worth a request that often.
  Future<void> _saveCastProgress(CastState state) async {
    final seconds = state.positionSeconds;
    if (seconds <= 0 || !state.playing) return;
    if (seconds == _lastCastSavedSeconds) return;

    final now = DateTime.now();
    final last = _lastCastSaveAt;
    if (last != null && now.difference(last) < _castProgressInterval) return;

    _lastCastSavedSeconds = seconds;
    _lastCastSaveAt = now;

    if (!ref.read(isSignedInProvider)) return;

    // The receiver's episode wins over this screen's. It advances the queue on
    // its own — by then `widget.id` is the episode the *user* opened, not the
    // one playing, and writing against it would credit progress to the wrong
    // episode and leave the real one unwatched.
    final episodeId =
        state.episodeId.isNotEmpty ? state.episodeId : _historyEpisodeId;
    final label = state.episodeLabel.isNotEmpty
        ? state.episodeLabel
        : widget.episodeLabel;

    try {
      await ref.read(accountApiProvider).saveProgress(
            provider: widget.provider,
            showId: _historyShowId,
            episodeId: episodeId,
            episodeLabel: label,
            progressSeconds: seconds,
            durationSeconds:
                state.durationSeconds > 0 ? state.durationSeconds : null,
          );
    } catch (_) {
      // Best-effort, exactly like the local path: a failed save must not
      // surface as an error over someone's cast.
    }
  }

  Future<void> _onCompleted() async {
    await _saveProgress(completed: true);
    if (!mounted) return;

    if (!_isOffline &&
        !_autoplayNextCancelled &&
        _contentType == 'episode' &&
        widget.showId != null) {
      final next = await ref.read(nextEpisodeProvider((
        provider: widget.provider,
        showId: widget.showId!,
        episodeId: widget.id,
      )).future);
      if (next != null && mounted) {
        _playNextEpisode(next);
        return;
      }
    }

    if (!mounted) return;
    showToast(context, "You're all caught up — that was the last episode.");
  }

  static String _nextEpisodeLabel(Episode episode) {
    final seasonNumber = episode.season?.number;
    final prefix = seasonNumber != null
        ? 'S${seasonNumber.toString().padLeft(2, '0')}'
        : '';
    return '${prefix}E${episode.number.toString().padLeft(2, '0')}';
  }

  void _playNextEpisode(Episode next) {
    final query = {
      'contentType': 'episode',
      'showId': widget.showId!,
      if (widget.title != null) 'title': widget.title!,
      'episodeLabel': _nextEpisodeLabel(next),
    };
    context.pushReplacement(
      '/watch/${widget.provider}/${Uri.encodeComponent(next.id)}?${Uri(queryParameters: query).query}',
    );
  }

  // ── Skip Intro/Recap/Credits (TheIntroDB) ────────────────────

  static const _skipSegmentLabels = {
    SkipSegmentType.intro: 'Skip Intro',
    SkipSegmentType.recap: 'Skip Recap',
    SkipSegmentType.credits: 'Skip Credits',
    SkipSegmentType.preview: 'Skip Preview',
  };

  /// tmdbId/imdbId/year for TheIntroDB — shared by [_loadIntroSegments] (the
  /// local Skip button) and [_buildCastPayload] (hints for the receiver's
  /// own lookup, see `CastPayload.tmdbId`/`imdbId`/`year`), so the two never
  /// resolve to different ids. `showDetailsProvider` is cached, so calling it
  /// again from the second caller costs no extra network round-trip.
  Future<(int? tmdbId, String? imdbId, int? year)> _resolveIntroDbIds() async {
    final provider = widget.provider;
    final showId = _historyShowId;
    if (provider.isEmpty || showId.isEmpty) return (null, null, null);

    // Wire ids for TMDB content look like "tv-<tmdbId>"/"movie-<tmdbId>"
    // (see core/providers/Tmdb.ts server-side). Every other provider here
    // carries no such id, so this just falls through to the server's own
    // fuzzy title match.
    final idMatch = RegExp(r'^(?:movie|tv)-(\d+)').firstMatch(showId);
    final tmdbId = idMatch != null ? int.tryParse(idMatch.group(1)!) : null;

    String? imdbId;
    int? year;
    try {
      final show = await ref
          .read(showDetailsProvider((provider: provider, showId: showId)).future);
      imdbId = _imdbIdOf(show);
      year = _releasedYearOf(show);
    } catch (_) {
      // Proceed on tmdbId/title alone — the server's fuzzy matcher can still hit.
    }

    return (tmdbId, imdbId, year);
  }

  /// Looks up skip segments for the title now playing — a port of
  /// `loadIntroSegments()` in `../../../../web/public/scripts/watch.js`.
  /// Downloads carry no guarantee of connectivity, so offline playback skips
  /// this entirely rather than making a doomed network call.
  Future<void> _loadIntroSegments() async {
    if (_isOffline) return;

    final provider = widget.provider;
    final title = widget.title;
    final showId = _historyShowId;
    if (provider.isEmpty || title == null || title.isEmpty || showId.isEmpty) {
      return;
    }

    final isEpisode = _contentType == 'episode';
    if (isEpisode && widget.showId == null) return;

    final (tmdbId, imdbId, year) = await _resolveIntroDbIds();

    int? season;
    int? episode;

    if (isEpisode) {
      try {
        final showRef = (provider: provider, showId: showId);
        final episodes = await ref.read(flatEpisodesProvider(showRef).future);
        Episode? current;
        for (final e in episodes) {
          if (e.id == widget.id) {
            current = e;
            break;
          }
        }
        if (current == null) return; // no season/episode to ask with — 400s
        season = current.season?.number;
        episode = current.number;
      } catch (_) {
        return; // an 18+ gate, a dead provider: no button, never blocks playback
      }
    }

    try {
      final data = await ref.read(contentApiProvider).introSegments(
            type: isEpisode ? 'tv' : 'movie',
            provider: provider,
            showId: showId,
            title: title,
            year: year,
            tmdbId: tmdbId,
            imdbId: imdbId,
            season: season,
            episode: episode,
          );
      if (mounted) setState(() => _introSegments = data);
    } catch (_) {
      // Best-effort — a failed lookup just means no skip button.
    }
  }

  /// Segments come from the "theintrodb" npm client, already normalized:
  /// `startMs` is always a number, `endMs` stays null to mean "runs to end
  /// of media" — checked in the same priority order as
  /// `SKIP_SEGMENT_LABELS`/`findActiveSkipSegment()` in `watch.js`.
  _ActiveSkipSegment? _findActiveSkipSegment(
      IntroDbMedia data, Duration position, Duration duration) {
    final tMs = position.inMilliseconds;
    final durMs = duration.inMilliseconds;
    for (final type in SkipSegmentType.values) {
      for (final seg in data.forType(type)) {
        final endMs = seg.endMs ?? durMs;
        if (tMs >= seg.startMs && tMs < endMs) {
          return _ActiveSkipSegment(
            type: type,
            end: Duration(milliseconds: endMs),
            runsToEnd: seg.endMs == null,
          );
        }
      }
    }
    return null;
  }

  /// Credits/preview with no end (runs to end of media) behave like "play
  /// next" when there is one, instead of seeking to the literal last frame.
  void _skipActiveSegment(_ActiveSkipSegment segment, Episode? nextEpisode) {
    final runsToEndOfMedia = segment.runsToEnd &&
        (segment.type == SkipSegmentType.credits ||
            segment.type == SkipSegmentType.preview);
    if (runsToEndOfMedia) {
      if (_contentType == 'episode' && nextEpisode != null) {
        _playNextEpisode(nextEpisode);
      } else if (_duration > Duration.zero) {
        _player.seek(_duration);
      }
      return;
    }
    _player.seek(segment.end);
  }

  // ── Actions ───────────────────────────────────────────────

  Future<void> _pickServer() async {
    if (_servers.isEmpty) return;

    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (var i = 0; i < _servers.length; i++)
              ListTile(
                // The sheet opens with nothing focused otherwise, so a remote
                // has to guess which way is "into" the list.
                autofocus: i == _serverIndex,
                onTap: () => Navigator.of(context).pop(i),
                title: Text(_servers[i].name.isEmpty
                    ? 'Server ${i + 1}'
                    : _servers[i].name),
                trailing: i == _serverIndex ? const Icon(Icons.check) : null,
              ),
          ],
        ),
      ),
    );

    if (picked == null || picked == _serverIndex) return;
    await _load(serverIndex: picked);
  }

  Future<void> _pickSubtitle() async {
    final tracks = _player.state.tracks.subtitle;
    final current = _player.state.track.subtitle;

    final picked = await showModalBottomSheet<SubtitleTrack>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              autofocus: current.id == 'no',
              title: const Text('Off'),
              trailing: current.id == 'no' ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop(SubtitleTrack.no()),
            ),
            for (final track in tracks)
              if (track.id != 'no' && track.id != 'auto')
                ListTile(
                  autofocus: track.id == current.id,
                  title: Text(track.title ?? track.language ?? track.id),
                  trailing:
                      track.id == current.id ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.of(context).pop(track),
                ),
          ],
        ),
      ),
    );

    if (picked != null) await _player.setSubtitleTrack(picked);
  }

  Future<void> _pickAudioTrack() async {
    final tracks = _player.state.tracks.audio;
    final current = _player.state.track.audio;

    final picked = await showModalBottomSheet<AudioTrack>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final track in tracks)
              if (track.id != 'no')
                ListTile(
                  autofocus: track.id == current.id,
                  title: Text(track.title ?? track.language ?? track.id),
                  trailing:
                      track.id == current.id ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.of(context).pop(track),
                ),
          ],
        ),
      ),
    );

    if (picked != null) await _player.setAudioTrack(picked);
  }

  Future<void> _pickQuality() async {
    final tracks = _player.state.tracks.video;
    final current = _player.state.track.video;

    final picked = await showModalBottomSheet<VideoTrack>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final track in tracks)
              ListTile(
                autofocus: track.id == current.id,
                title: Text(track.h != null ? '${track.h}p' : track.id),
                trailing:
                    track.id == current.id ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(track),
              ),
          ],
        ),
      ),
    );

    if (picked != null) await _player.setVideoTrack(picked);
  }

  Future<void> _share() async {
    if (!ref.read(isSignedInProvider)) {
      showToast(context, 'Sign in to share.', isError: true);
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ShareSheet(
        provider: widget.provider,
        showId: _historyShowId,
        title: widget.title ?? 'this title',
        episodeId: _historyEpisodeId,
        episodeLabel: widget.episodeLabel,
        // Sharing from the player defaults to "from where I am now" — that's
        // what the clip fields on the share endpoint are for.
        suggestedClipStart: _position.inSeconds,
      ),
    );
  }

  /// The Cast button. Once a session is up it opens the controls rather than
  /// the device picker: with a cast running, "cast" means "control what's
  /// casting", and reaching the transport controls should not require going
  /// through a list of devices you already chose from. The picker stays one
  /// tap away from inside the panel.
  Future<void> _openCast() async {
    if (ref.read(castSessionProvider).value != null) {
      await _openCastControls();
      return;
    }
    await _openCastSheet();
  }

  Future<void> _openCastControls() async {
    // The queue the receiver was given, for the episode picker. Rebuilt rather
    // than remembered: the receiver may have advanced episodes on its own, and
    // this is the same list at the same indices either way.
    final payload = await _buildCastPayload();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => CastControlPanel(
        episodes: payload?.episodes ?? const [],
        onCastHere: _castCurrentStream,
        onChooseDevice: () {
          Navigator.of(context).pop();
          _openCastSheet();
        },
      ),
    );
  }

  Future<void> _openCastSheet() async {
    if (_rawStreamUrl == null) {
      showToast(context, 'Nothing to cast yet.', isError: true);
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => CastSheet(onCastHere: _castCurrentStream),
    );
  }

  /// Hands the current stream to whatever session is connected. Playback stays
  /// paused locally while the receiver takes over, matching the web sender.
  ///
  /// This is the *only* place the app issues a LOAD, and it is reached two
  /// ways: automatically when a session goes active (see [_wireCastAutoLoad]),
  /// and explicitly when the user asks to play on a device that is already
  /// connected. Having it live in the device picker instead is what made a
  /// receiver that was already running — launched on the TV, idle, waiting —
  /// impossible to give a stream to.
  Future<void> _castCurrentStream() async {
    final rawUrl = _rawStreamUrl;
    if (rawUrl == null) {
      showToast(context, 'Nothing to cast yet.', isError: true);
      return;
    }

    // Claim the session before the first await: _buildCastPayload does network
    // work, and a second trigger arriving during it would issue a duplicate
    // LOAD — which the receiver honours by restarting the stream.
    if (_castLoading) return;
    _castLoading = true;
    _castHandedOff = true;
    _castLoadedSessionId = ref.read(castSessionProvider).value?.sessionID;

    try {
      await _player.pause();
      if (!mounted) return;

      final payload = await _buildCastPayload();
      if (!mounted) return;

      // Re-read: the id can arrive after the handshake this load raced.
      _castLoadedSessionId =
          ref.read(castSessionProvider).value?.sessionID ?? _castLoadedSessionId;

      await runGuarded(context, () async {
        await ref.read(castServiceProvider).load(
              rawUrl: rawUrl,
              title: widget.title ?? 'Streamio',
              subtitle: widget.episodeLabel,
              startFrom: _position,
              payload: payload,
              duration: _duration > Duration.zero ? _duration : null,
              // Saturn resolves to a progressive MP4; declaring that as HLS
              // makes the receiver fail to parse it.
              progressive: (_lastSource?.type ?? '').startsWith('video/'),
              referer: _castReferer,
            );
      });
    } finally {
      _castLoading = false;
    }
  }

  /// Builds the `customData` the Streamio receiver reads, so it can render
  /// artwork and episode context, advance episodes on its own once this app is
  /// gone, and re-resolve a stream whose signed URL expires mid-playback.
  ///
  /// Best-effort by design: every lookup here is metadata, and none of it is
  /// worth failing a cast over. Whatever couldn't be resolved is simply
  /// omitted, and the receiver degrades field by field.
  Future<CastPayload?> _buildCastPayload() async {
    final apiBase = ref.read(currentServerUrlProvider);
    final cast = ref.read(castServiceProvider);
    // `castProxyBase` in the payload stays the plain server prefix, exactly as
    // the browser sender leaves it: the receiver reuses it to build URLs for
    // streams it resolves itself (next episode, recovery), which are not this
    // stream and need not share its Referer. The subtitle URLs below are built
    // from *this* stream's resolve, so they do carry it.
    final proxyBase = cast.config?.proxyBase ?? '';
    if (apiBase == null) return null;

    final isEpisode = _contentType == 'episode';
    final showRef = (provider: widget.provider, showId: _historyShowId);

    Show? show;
    List<Episode> episodes = const [];
    try {
      show = await ref.read(showDetailsProvider(showRef).future);
      if (isEpisode) {
        episodes = await ref.read(flatEpisodesProvider(showRef).future);
      }
    } catch (_) {
      // An 18+ gate, an offline moment, a provider that failed: cast anyway.
    }

    final index = episodes.indexWhere((e) => e.id == widget.id);
    final current = index == -1 ? null : episodes[index];
    final server =
        _serverIndex < _servers.length ? _servers[_serverIndex] : null;
    final (tmdbId, imdbId, year) = await _resolveIntroDbIds();

    return CastPayload(
      apiBase: apiBase,
      castProxyBase: proxyBase,
      provider: widget.provider,
      contentType: _contentType,
      showId: _historyShowId,
      tmdbId: tmdbId,
      imdbId: imdbId ?? '',
      year: year,
      showTitle: show?.title ?? widget.title ?? 'Streamio',
      description: _overviewOf(show),
      poster: _posterOf(show),
      backdrop: _backdropOf(show),
      seasonId: current?.season?.id ?? '',
      seasonNumber: current?.season?.number,
      episodeId: isEpisode ? widget.id : '',
      episodeNumber: current?.number,
      episodeTitle: current?.title ?? '',
      episodeLabel: widget.episodeLabel ?? '',
      durationSeconds:
          _duration > Duration.zero ? _duration.inSeconds : _runtimeOf(show),
      serverName: server?.name ?? '',
      serverIndex: _serverIndex,
      subtitles: _castSubtitles(cast.castProxyBase(referer: _castReferer)),
      episodes: [for (final e in episodes) CastEpisodeRef.fromEpisode(e)],
      episodeIndex: index,
      autoplayNext: !_autoplayNextCancelled,
      upNextSeconds: _nextEpisodeThreshold.inSeconds,
    );
  }

  /// The `Referer` this stream's resolver asked for, forwarded to the cast
  /// proxy as `ref=`. Empty for the providers that don't need one. Without it
  /// the proxy sends the media host's own origin, which some CDNs 403 — the
  /// browser sender folds the same value in (`castProxyUrl()` in
  /// `../web/public/scripts/watch.js`), which is why those titles cast from a
  /// browser and fail from here.
  String get _castReferer => refererOf(_lastSource?.headers ?? const {});

  /// Subtitle URLs have to be proxied for the receiver: upstream VTT is often
  /// plain http (mixed content) and carries no CORS header, either of which
  /// makes CAF drop the track silently.
  List<CastSubtitle> _castSubtitles(String proxyBase) {
    final subs = _lastSource?.subtitles ?? const <Subtitle>[];
    if (proxyBase.isEmpty) return const [];
    return [
      for (final s in subs)
        if (s.file.isNotEmpty)
          CastSubtitle(
            label: s.label,
            lang: s.label,
            url: '$proxyBase${Uri.encodeComponent(s.file)}',
            isDefault: s.isDefault || s.initialDefault,
          ),
    ];
  }

  static String _overviewOf(Show? show) => switch (show) {
        TvShow(:final overview) => overview ?? '',
        Movie(:final overview) => overview ?? '',
        _ => '',
      };

  static String _posterOf(Show? show) => switch (show) {
        TvShow(:final poster) => poster ?? '',
        Movie(:final poster) => poster ?? '',
        _ => '',
      };

  static String _backdropOf(Show? show) => switch (show) {
        TvShow(:final banner, :final poster) => banner ?? poster ?? '',
        Movie(:final banner, :final poster) => banner ?? poster ?? '',
        _ => '',
      };

  static int? _runtimeOf(Show? show) => switch (show) {
        TvShow(:final runtime) => runtime == null ? null : runtime * 60,
        Movie(:final runtime) => runtime == null ? null : runtime * 60,
        _ => null,
      };

  static String? _imdbIdOf(Show? show) => switch (show) {
        TvShow(:final imdbId) => imdbId,
        Movie(:final imdbId) => imdbId,
        _ => null,
      };

  static int? _releasedYearOf(Show? show) => switch (show) {
        TvShow(:final released) => released?.year,
        Movie(:final released) => released?.year,
        _ => null,
      };

  void _openRoomPanel() {
    final code = widget.roomCode;
    if (code == null) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => RoomPanel(
        code: code,
        onRemoteState: _applyRemoteState,
        localPosition: () => _position,
        localPlaying: () => _playing,
      ),
    );
  }

  /// Applies another member's state without echoing it back: the room panel
  /// owns the socket, and only *local* play/pause/seek is broadcast.
  Future<void> _applyRemoteState(RoomState state) async {
    final target = Duration(seconds: state.positionSeconds);
    if ((target - _position).abs() > const Duration(seconds: 2)) {
      // The room's position wins over this device's stored resume point.
      _userSeeked = true;
      await _player.seek(target);
    }
    if (state.playing != _playing) {
      state.playing ? await _player.play() : await _player.pause();
    }
  }

  // ── Keyboard shortcuts ───────────────────────────────────────
  //
  // Desktop/web only in practice (touch platforms don't send key events
  // here), but harmless everywhere. Bound via `Shortcuts`/`Actions` rather
  // than a raw key listener so they win over Flutter's *default* shortcuts —
  // on desktop, arrow keys are bound app-wide to move focus between
  // focusable widgets (`DirectionalFocusIntent`). Once a control button took
  // focus (autofocus, a prior Tab, or a click), the arrow keys stopped
  // seeking and started hopping between buttons instead — from the focused
  // widget, key lookup walks up through the nearest `Shortcuts` first, and
  // that used to be the app-level default, not this one. Placing this
  // `Shortcuts` as an ancestor of the controls intercepts the same keys
  // first, so the transport commands keep working no matter which button
  // last had focus.

  Map<ShortcutActivator, Intent> get _playerShortcuts => {
        const SingleActivator(LogicalKeyboardKey.space):
            const _PlayPauseIntent(),
        const SingleActivator(LogicalKeyboardKey.mediaPlayPause):
            const _PlayPauseIntent(),
        const SingleActivator(LogicalKeyboardKey.mediaPlay):
            const _PlayPauseIntent(),
        const SingleActivator(LogicalKeyboardKey.mediaPause):
            const _PlayPauseIntent(),
        const SingleActivator(LogicalKeyboardKey.mediaRewind):
            const _SeekIntent(Duration(seconds: -10)),
        const SingleActivator(LogicalKeyboardKey.mediaFastForward):
            const _SeekIntent(Duration(seconds: 10)),
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const _SeekIntent(Duration(seconds: -10)),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const _SeekIntent(Duration(seconds: 10)),
        const SingleActivator(LogicalKeyboardKey.escape): const _BackIntent(),
      };

  /// Whether the arrow keys should seek rather than move focus.
  ///
  /// On a keyboard they always seek — that's what the `Shortcuts` above are
  /// for, and a mouse is there to press the buttons. On a **remote** the
  /// arrows are the only way to move between the transport buttons, and this
  /// `Shortcuts` deliberately sits above every one of them, so an
  /// always-enabled seek action makes each control past the focused one
  /// permanently unreachable — which is exactly what "the watch page isn't
  /// controllable" looked like. So while the overlay is up on a television
  /// the seek action reports itself disabled, and the key falls through to
  /// Flutter's default [DirectionalFocusIntent]; the on-screen ±10s buttons
  /// do the seeking instead. With the overlay hidden there is nothing to
  /// traverse, so the arrows go back to seeking.
  bool get _arrowsSeek => !(_tv && _controlsVisible);

  Map<Type, Action<Intent>> get _playerActions => {
        _PlayPauseIntent: CallbackAction<_PlayPauseIntent>(
          onInvoke: (_) => _player.playOrPause(),
        ),
        _SeekIntent: _ConditionalCallbackAction<_SeekIntent>(
          isActive: () => _arrowsSeek,
          onInvoke: (intent) => _seekBy(intent.offset),
        ),
        _BackIntent: CallbackAction<_BackIntent>(
          onInvoke: (_) => context.canPop() ? context.pop() : context.go('/'),
        ),
      };

  /// Keys the remote's transport buttons send. They act on the player
  /// whatever the overlay is doing, so the wake-up handler in [build] must
  /// not swallow them.
  static final _transportKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.mediaPlay,
    LogicalKeyboardKey.mediaPause,
    LogicalKeyboardKey.mediaPlayPause,
    LogicalKeyboardKey.mediaStop,
    LogicalKeyboardKey.mediaRewind,
    LogicalKeyboardKey.mediaFastForward,
  };

  // ── UI ────────────────────────────────────────────────────

  static String _formatTime(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final showChrome = _loading || _error != null || _controlsVisible;

    // Watched regardless of _autoplayNextCancelled: a cancelled autoplay
    // countdown shouldn't also disable "Skip Credits" jumping to the next
    // episode below — only the prompt's own visibility is gated on it.
    Episode? nextEpisode;
    if (!_isOffline && _contentType == 'episode' && widget.showId != null) {
      nextEpisode = ref
          .watch(nextEpisodeProvider((
            provider: widget.provider,
            showId: widget.showId!,
            episodeId: widget.id,
          )))
          .value;
    }
    final remaining =
        _duration > Duration.zero ? _duration - _position : Duration.zero;
    final showNextEpisodePrompt = !_autoplayNextCancelled &&
        !_loading &&
        _error == null &&
        nextEpisode != null &&
        remaining > Duration.zero &&
        remaining <= _nextEpisodeThreshold;

    // Skip Intro/Recap/Credits/Preview — never shown together with the
    // next-episode prompt (mirrors watch.js's maybeShowSkipSegment()).
    final activeSkipSegment = !showNextEpisodePrompt &&
            !_loading &&
            _error == null &&
            _introSegments != null &&
            _duration > Duration.zero
        ? _findActiveSkipSegment(_introSegments!, _position, _duration)
        : null;

    return Shortcuts(
      shortcuts: _playerShortcuts,
      child: Actions(
        actions: _playerActions,
        child: Focus(
          focusNode: _screenFocus,
          autofocus: true,
          // A D-pad remote has no touch/pointer events, so nothing else here
          // shows the controls overlay or resets its auto-hide timer — the
          // GestureDetector.onTap and Listener.onPointerDown below only fire
          // for touch/mouse.
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;

            if (_controlsVisible) {
              _resetHideControlsTimer();
              return KeyEventResult.ignored;
            }

            // Transport keys act on the player directly; waking the overlay
            // is a courtesy, not a reason to eat the press.
            if (_transportKeys.contains(event.logicalKey)) {
              _showControls();
              return KeyEventResult.ignored;
            }

            _showControls();
            // On a remote the overlay is the only way to reach anything, so
            // the press that summons it must not *also* fire whatever it
            // landed on — pressing OK to see the controls should not toggle
            // playback in the same breath. With a keyboard the shortcuts are
            // the point, so the event falls through there.
            return _tv ? KeyEventResult.handled : KeyEventResult.ignored;
          },
          child: _buildScaffold(showChrome, showNextEpisodePrompt, nextEpisode,
              remaining, activeSkipSegment),
        ),
      ),
    );
  }

  Widget _buildScaffold(
    bool showChrome,
    bool showNextEpisodePrompt,
    Episode? nextEpisode,
    Duration remaining,
    _ActiveSkipSegment? activeSkipSegment,
  ) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _error != null
                ? ErrorState(
                    error: _error!,
                    onRetry: _load,
                    scrollable: false,
                  )
                : _loading
                    ? const Center(child: CircularProgressIndicator())
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _toggleControls,
                        child: Video(
                            controller: _controller, controls: NoVideoControls),
                      ),
          ),
          // Says out loud what [_handleStreamError] is doing quietly, so a
          // stream that has hiccuped reads as "working on it" rather than as
          // a frozen picture. Never shown alongside the error state: reaching
          // that means recovery is over.
          if (_reconnecting && _error == null)
            const Positioned.fill(
              child: SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  // Clears the top bar, which is drawn over the same corner.
                  child: Padding(
                    padding: EdgeInsets.only(top: 72),
                    child: _ReconnectingBanner(),
                  ),
                ),
              ),
            ),
          if (!_loading && _error == null)
            // Positioned.fill: a bare Stack whose children are all Positioned
            // collapses to zero size under the outer Stack's loose
            // constraints, and the overlay would never be visible.
            Positioned.fill(
              child: Listener(
                onPointerDown: (_) => _resetHideControlsTimer(),
                child: IgnorePointer(
                  ignoring: !showChrome,
                  // The pointer half of "hidden" was already handled;
                  // without the focus half, a faded-out overlay still holds
                  // perfectly good focus targets, so a remote spends its
                  // presses on buttons nobody can see.
                  child: ExcludeFocus(
                    excluding: !showChrome,
                    child: AnimatedOpacity(
                      opacity: showChrome ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Stack(
                        children: [
                          _controlsOverlay(),
                          Positioned(
                              top: 0, left: 0, right: 0, child: _topBar()),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            Positioned(top: 0, left: 0, right: 0, child: _topBar()),
          // Outside the controls' fade/hide group on purpose: this should
          // stay up (and tappable) through the auto-hide timer, the same way
          // Netflix's own prompt does.
          // showNextEpisodePrompt is only true when nextEpisode is non-null
          // (see build()), but that promotion doesn't cross the call into
          // this method, hence the `!`.
          if (showNextEpisodePrompt)
            _nextEpisodePrompt(nextEpisode!, remaining)
          else if (activeSkipSegment != null)
            _skipSegmentPrompt(activeSkipSegment, nextEpisode),
        ],
      ),
    );
  }

  Widget _skipSegmentPrompt(_ActiveSkipSegment segment, Episode? nextEpisode) {
    return Positioned(
      right: 16,
      bottom: 100,
      child: Material(
        color: Colors.transparent,
        child: OutlinedButton(
          onPressed: () => _skipActiveSegment(segment, nextEpisode),
          style: OutlinedButton.styleFrom(
            backgroundColor: const Color(0xE61A1A1A),
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white24),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
          child: Text(
            _skipSegmentLabels[segment.type] ?? 'Skip',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  Widget _nextEpisodePrompt(Episode next, Duration remaining) {
    final seconds =
        remaining.inSeconds.clamp(0, _nextEpisodeThreshold.inSeconds);
    return Positioned(
      right: 16,
      bottom: 100,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 260,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xE61A1A1A),
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black54, blurRadius: 12, offset: Offset(0, 4)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Next: ${_nextEpisodeLabel(next)}',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: Colors.white70, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Cancel',
                    onPressed: () =>
                        setState(() => _autoplayNextCancelled = true),
                  ),
                ],
              ),
              if (next.title != null) ...[
                const SizedBox(height: 2),
                Text(
                  next.title!,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _playNextEpisode(next),
                  icon: const Icon(Icons.play_arrow),
                  label: Text('Play now · ${seconds}s'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/'),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title ?? 'Now playing',
                    style: const TextStyle(color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.episodeLabel != null || _isOffline)
                    Text(
                      [
                        if (widget.episodeLabel != null) widget.episodeLabel!,
                        if (_isOffline) 'Offline',
                      ].join(' · '),
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                ],
              ),
            ),
            // Offline downloads live on this device only — a receiver on the
            // network can't reach the loopback server that serves them.
            if (!_isOffline &&
                (ref.watch(castAvailableProvider).value ?? false))
              IconButton(
                icon: Icon(
                  ref.watch(castSessionProvider).value != null
                      ? Icons.cast_connected
                      : Icons.cast,
                  color: Colors.white,
                ),
                tooltip: 'Cast',
                onPressed: _openCast,
              ),
            if (widget.roomCode != null)
              IconButton(
                icon: const Icon(Icons.groups, color: Colors.white),
                tooltip: 'Watch party',
                onPressed: _openRoomPanel,
              ),
            if (!_isOffline)
              IconButton(
                icon: const Icon(Icons.ios_share, color: Colors.white),
                tooltip: 'Share',
                onPressed: _share,
              ),
          ],
        ),
      ),
    );
  }

  Widget _controlsOverlay() {
    final duration = _duration.inMilliseconds > 0 ? _duration : Duration.zero;
    final maxMs = duration.inMilliseconds.toDouble();
    final valueMs =
        _position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble();

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(_formatTime(_position),
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12)),
                  Expanded(
                    // Never focusable: the screen-level ±10s arrowLeft/Right
                    // Shortcuts already own seeking, and if this ever took
                    // focus its own arrow-key drag handling would be
                    // intercepted by that ancestor Shortcuts anyway (it's
                    // placed to win over any focused descendant's default key
                    // behavior — see _playerShortcuts above). It's kept
                    // purely as a visual progress indicator here.
                    child: FocusTraversalGroup(
                      descendantsAreFocusable: false,
                      child: Slider(
                        value: maxMs > 0 ? valueMs : 0,
                        max: maxMs > 0 ? maxMs : 1,
                        onChangeStart: maxMs > 0
                            ? (_) => setState(() => _scrubbing = true)
                            : null,
                        onChanged: maxMs > 0
                            ? (value) => setState(() => _position =
                                Duration(milliseconds: value.round()))
                            : null,
                        onChangeEnd: maxMs > 0
                            ? (value) {
                                _userSeeked = true;
                                _player.seek(
                                    Duration(milliseconds: value.round()));
                                setState(() => _scrubbing = false);
                              }
                            : null,
                      ),
                    ),
                  ),
                  Text(_formatTime(duration),
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
              FocusTraversalGroup(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.replay_10, color: Colors.white),
                        onPressed: () => _seekBy(const Duration(seconds: -10)),
                      ),
                      IconButton(
                        focusNode: _playPauseFocus,
                        autofocus: _tv,
                        iconSize: 44,
                        icon: Icon(
                          _playing
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                          color: Colors.white,
                        ),
                        onPressed: _player.playOrPause,
                      ),
                      IconButton(
                        icon: const Icon(Icons.forward_10, color: Colors.white),
                        onPressed: () => _seekBy(const Duration(seconds: 10)),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.closed_caption_outlined,
                            color: Colors.white),
                        tooltip: 'Subtitles',
                        onPressed: _pickSubtitle,
                      ),
                      IconButton(
                        icon: const Icon(Icons.audiotrack_outlined,
                            color: Colors.white),
                        tooltip: 'Audio track',
                        onPressed: _pickAudioTrack,
                      ),
                      IconButton(
                        icon:
                            const Icon(Icons.hd_outlined, color: Colors.white),
                        tooltip: 'Quality',
                        onPressed: _pickQuality,
                      ),
                      if (!_isOffline && _servers.length > 1)
                        IconButton(
                          icon: const Icon(Icons.dns_outlined,
                              color: Colors.white),
                          tooltip: 'Source server',
                          onPressed: _pickServer,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayPauseIntent extends Intent {
  const _PlayPauseIntent();
}

class _SeekIntent extends Intent {
  const _SeekIntent(this.offset);
  final Duration offset;
}

class _BackIntent extends Intent {
  const _BackIntent();
}

/// The skip segment covering the player's current position, if any — the
/// result of [_WatchScreenState._findActiveSkipSegment].
class _ActiveSkipSegment {
  const _ActiveSkipSegment({
    required this.type,
    required this.end,
    required this.runsToEnd,
  });

  final SkipSegmentType type;
  final Duration end;
  final bool runsToEnd;
}

/// A [CallbackAction] that can turn itself off.
///
/// A *disabled* action is the mechanism that lets a key fall through: when
/// [Shortcuts] resolves an activator to an action that reports itself
/// disabled, it returns [KeyEventResult.ignored] and the event keeps
/// travelling up the focus chain — reaching, eventually, the app-level
/// default that moves focus. Returning early from a plain `CallbackAction`
/// would not do this: the action would still count as handled.
class _ConditionalCallbackAction<T extends Intent> extends CallbackAction<T> {
  _ConditionalCallbackAction({required super.onInvoke, required this.isActive});

  final bool Function() isActive;

  @override
  bool isEnabled(T intent) => isActive();
}

/// Shown while a reported stream error is being waited out or recovered from
/// (see `_handleStreamError`). Non-interactive on purpose — it must not take
/// focus away from the controls on a D-pad remote.
class _ReconnectingBanner extends StatelessWidget {
  const _ReconnectingBanner();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text('Reconnecting…',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wraps a libmpv error string so [ErrorState] shows the real message rather
/// than its generic fallback.
class PlaybackFailure implements Exception, UserFacingError {
  const PlaybackFailure(this.message);

  @override
  final String message;

  @override
  String toString() => message;
}
