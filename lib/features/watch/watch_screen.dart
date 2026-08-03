import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/models/models.dart';
import '../../shared/user_facing_error.dart';
import '../../shared/widgets/async_states.dart';
import '../../state/api_providers.dart';
import '../../state/auth_providers.dart';
import '../../state/download_providers.dart';
import '../../state/server_config_provider.dart';
import '../../state/cast_providers.dart';
import '../social/share_sheet.dart';
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

  late final Player _player = Player();

  /// Hardware-accelerated rendering on Linux goes through an ANGLE/EGL
  /// texture path that's broken on the NVIDIA proprietary driver — the
  /// video surface comes up solid blue instead of decoded frames. Software
  /// rendering there is the documented media_kit workaround; other
  /// platforms keep the (working) default.
  late final VideoController _controller = VideoController(
    _player,
    configuration: VideoControllerConfiguration(
      enableHardwareAcceleration: !Platform.isLinux,
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

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _scrubbing = false;

  Timer? _progressTimer;
  int _lastSavedSeconds = -1;

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

  /// Bumped on every [_load]. Lets a stray [_confirmResumePosition] from a
  /// superseded load (server switch, retry) recognize it's stale and stop.
  int _loadGeneration = 0;

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
    _load();
    _resetHideControlsTimer();
  }

  void _wirePlayerStreams() {
    _subscriptions.addAll([
      _player.stream.position.listen((position) {
        if (!mounted || _scrubbing) return;
        setState(() => _position = position);
      }),
      _player.stream.duration.listen((duration) {
        if (!mounted) return;
        setState(() => _duration = duration);
      }),
      _player.stream.playing.listen((playing) {
        if (!mounted) return;
        setState(() {
          _playing = playing;
          // Nothing to auto-hide while paused — show the controls the user
          // just asked for by pausing.
          if (!playing) _controlsVisible = true;
        });
        _resetHideControlsTimer();
        // Pausing is the save point users expect to survive a force-quit.
        if (!playing) unawaited(_saveProgress());
      }),
      _player.stream.completed.listen((completed) {
        if (completed) unawaited(_onCompleted());
      }),
      _player.stream.error.listen((message) {
        if (!mounted || message.isEmpty) return;
        setState(() {
          _error = PlaybackFailure(message);
          _loading = false;
        });
      }),
    ]);
  }

  @override
  void dispose() {
    // Fire-and-forget: the widget is going away, but the last position is
    // worth persisting.
    unawaited(_saveProgress());
    _progressTimer?.cancel();
    _hideControlsTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _player.dispose();
    if (_tempManifestPath != null) {
      File(_tempManifestPath!).delete().ignore();
    }
    if (_isOffline) unawaited(ref.read(localMediaServerProvider).stop());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ── Loading ───────────────────────────────────────────────

  Future<void> _load({int? serverIndex}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final generation = ++_loadGeneration;

    try {
      final start = await _resolveStartPosition();
      final media = _isOffline
          ? await _offlineMedia(start: start)
          : await _onlineMedia(serverIndex: serverIndex ?? _serverIndex, start: start);

      _resumeConfirmed = start == null;
      _userSeeked = false;
      await _player.open(media);
      if (mounted) setState(() => _loading = false);
      _startProgressTimer();
      unawaited(_confirmResumePosition(start, generation));
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

        debugPrint('[resume] attempt=$attempt fell back to $position, re-seeking');
        settled = 0;
        await _player.seek(start);
      }
    } finally {
      if (mounted && generation == _loadGeneration) _resumeConfirmed = true;
    }
  }

  Future<Media> _offlineMedia({Duration? start}) async {
    final url = await ref.read(localMediaServerProvider).serve(widget.downloadId!);
    return Media(url, start: start);
  }

  Future<Media> _onlineMedia({required int serverIndex, Duration? start}) async {
    final result = await resolvePlayback(
      ref.read(contentApiProvider),
      widget.provider,
      widget.id,
      contentType: _contentType,
      knownServers: _servers.isEmpty ? null : _servers,
      serverIndex: serverIndex,
    );

    _servers = result.servers;
    _serverIndex = result.serverIndex;

    final source = result.source;
    var uri = source.url;
    _rawStreamUrl = source.url.isEmpty ? null : source.url;

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
      if (baseUrl != null) uri = proxiedSourceUrl(uri, baseUrl);
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
      setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _resetHideControlsTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
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
            durationSeconds: _duration.inSeconds > 0 ? _duration.inSeconds : null,
            completed: completed,
          );
    } catch (_) {
      // Progress is best-effort; a failed save must not interrupt playback.
    }
  }

  Future<void> _onCompleted() async {
    await _saveProgress(completed: true);
    if (!mounted) return;
    // `watch.js` shows a next-episode prompt here. The episode list lives on
    // the details screen, so this points back there rather than guessing at
    // the next id.
    showToast(context, 'Finished — pick the next episode from the title page.');
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
                onTap: () => Navigator.of(context).pop(i),
                title: Text(
                    _servers[i].name.isEmpty ? 'Server ${i + 1}' : _servers[i].name),
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
              title: const Text('Off'),
              trailing: current.id == 'no' ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop(SubtitleTrack.no()),
            ),
            for (final track in tracks)
              if (track.id != 'no' && track.id != 'auto')
                ListTile(
                  title: Text(track.title ?? track.language ?? track.id),
                  trailing: track.id == current.id ? const Icon(Icons.check) : null,
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
                  title: Text(track.title ?? track.language ?? track.id),
                  trailing: track.id == current.id ? const Icon(Icons.check) : null,
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
                title: Text(track.h != null ? '${track.h}p' : track.id),
                trailing: track.id == current.id ? const Icon(Icons.check) : null,
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

  /// Hands the current stream to a Chromecast. Playback stays paused locally
  /// while the receiver takes over, matching what the web sender does.
  Future<void> _openCastSheet() async {
    final rawUrl = _rawStreamUrl;
    if (rawUrl == null) {
      showToast(context, 'Nothing to cast yet.', isError: true);
      return;
    }

    await _player.pause();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => CastSheet(
        rawUrl: rawUrl,
        title: widget.title ?? 'Streamio',
        subtitle: widget.episodeLabel,
        startFrom: _position,
      ),
    );
  }

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
                        child: Video(controller: _controller, controls: NoVideoControls),
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
                  child: AnimatedOpacity(
                    opacity: showChrome ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Stack(
                      children: [
                        _controlsOverlay(),
                        Positioned(top: 0, left: 0, right: 0, child: _topBar()),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            Positioned(top: 0, left: 0, right: 0, child: _topBar()),
        ],
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
              onPressed: () => context.canPop() ? context.pop() : context.go('/'),
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
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                ],
              ),
            ),
            // Offline downloads live on this device only — a receiver on the
            // network can't reach the loopback server that serves them.
            if (!_isOffline && (ref.watch(castAvailableProvider).valueOrNull ?? false))
              IconButton(
                icon: Icon(
                  ref.watch(castSessionProvider).valueOrNull != null
                      ? Icons.cast_connected
                      : Icons.cast,
                  color: Colors.white,
                ),
                tooltip: 'Cast',
                onPressed: _openCastSheet,
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
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: maxMs > 0 ? valueMs : 0,
                      max: maxMs > 0 ? maxMs : 1,
                      onChangeStart: maxMs > 0
                          ? (_) => setState(() => _scrubbing = true)
                          : null,
                      onChanged: maxMs > 0
                          ? (value) => setState(() =>
                              _position = Duration(milliseconds: value.round()))
                          : null,
                      onChangeEnd: maxMs > 0
                          ? (value) {
                              _userSeeked = true;
                              _player.seek(Duration(milliseconds: value.round()));
                              setState(() => _scrubbing = false);
                            }
                          : null,
                    ),
                  ),
                  Text(_formatTime(duration),
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.replay_10, color: Colors.white),
                      onPressed: () {
                        _userSeeked = true;
                        _player.seek(_position - const Duration(seconds: 10));
                      },
                    ),
                    IconButton(
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
                      onPressed: () {
                        _userSeeked = true;
                        _player.seek(_position + const Duration(seconds: 10));
                      },
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.closed_caption_outlined,
                          color: Colors.white),
                      tooltip: 'Subtitles',
                      onPressed: _pickSubtitle,
                    ),
                    IconButton(
                      icon: const Icon(Icons.audiotrack_outlined, color: Colors.white),
                      tooltip: 'Audio track',
                      onPressed: _pickAudioTrack,
                    ),
                    IconButton(
                      icon: const Icon(Icons.hd_outlined, color: Colors.white),
                      tooltip: 'Quality',
                      onPressed: _pickQuality,
                    ),
                    if (!_isOffline && _servers.length > 1)
                      IconButton(
                        icon: const Icon(Icons.dns_outlined, color: Colors.white),
                        tooltip: 'Source server',
                        onPressed: _pickServer,
                      ),
                  ],
                ),
              ),
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
