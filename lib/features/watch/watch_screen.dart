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
  late final VideoController _controller = VideoController(_player);

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

  /// The resume point handed to [Media.start]. mpv applies that via an
  /// `on_load` hook, but for network HLS the demuxer often isn't seekable
  /// until the stream is actually open, so the hook's seek can silently lose
  /// to mpv landing back at 0 once real playback begins. Re-asserted once
  /// (below) as soon as a real duration confirms the stream is up.
  Duration? _pendingResumeStart;

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

        final pending = _pendingResumeStart;
        if (pending != null && duration > Duration.zero) {
          _pendingResumeStart = null;
          // mpv's own resume landed near 0 despite Media.start — force it.
          if ((_player.state.position - pending).abs() >
              const Duration(seconds: 5)) {
            _player.seek(pending);
          }
        }
      }),
      _player.stream.playing.listen((playing) {
        if (!mounted) return;
        setState(() => _playing = playing);
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

    try {
      final start = await _resolveStartPosition();
      _pendingResumeStart = start;
      final media = _isOffline
          ? await _offlineMedia(start: start)
          : await _onlineMedia(serverIndex: serverIndex ?? _serverIndex, start: start);

      await _player.open(media);
      if (mounted) setState(() => _loading = false);
      _startProgressTimer();
    } catch (err) {
      if (mounted) {
        setState(() {
          _error = err;
          _loading = false;
        });
      }
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
    return start > 5 ? Duration(seconds: start) : null;
  }

  // ── Progress ──────────────────────────────────────────────

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(_progressInterval, (_) => _saveProgress());
  }

  Future<void> _saveProgress({bool completed = false}) async {
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
                    : Video(controller: _controller, controls: NoVideoControls),
          ),
          if (!_loading && _error == null) _controlsOverlay(),
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
                      onPressed: () =>
                          _player.seek(_position - const Duration(seconds: 10)),
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
                      onPressed: () =>
                          _player.seek(_position + const Duration(seconds: 10)),
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
