import 'dart:io';

import 'package:flutter_chrome_cast/cast_context.dart';
import 'package:flutter_chrome_cast/common.dart';
import 'package:flutter_chrome_cast/discovery.dart';
import 'package:flutter_chrome_cast/entities.dart';
import 'package:flutter_chrome_cast/enums/text_track_type.dart';
import 'package:flutter_chrome_cast/enums/track_type.dart';
import 'package:flutter_chrome_cast/media.dart';
import 'package:flutter_chrome_cast/models.dart';
import 'package:flutter_chrome_cast/session.dart';

import '../api/content_api.dart';
import '../config/cast_receiver_config.dart';
import '../models/models.dart';
import 'cast_control_channel.dart';
import 'cast_payload.dart';
import 'cast_state.dart';

export 'cast_control_channel.dart' show kCastControlNamespace;
export 'cast_payload.dart';
export 'cast_state.dart';

/// Chromecast sender.
///
/// Two details here are specific to Streamio rather than to Cast in general:
///
///  * **The receiver app id is resolved, not constant.** Casting goes through a
///    custom CAF receiver (its own repo, `cast-receiver`) because the
///    default media receiver mishandles the demuxed audio/video HLS these
///    providers emit. The id normally comes from the server
///    (`GET /api/cast-config`,
///    serving `CAST_RECEIVER_APP_ID`), but a device-local override wins over
///    it — see [CastReceiverConfig] for why that has to exist. When the server
///    can't be reached the chain ends at [kStreamioReceiverAppId] rather than
///    at Google's default media receiver, which would mishandle these streams.
///  * **The URL sent to the receiver must be absolute and proxied.** The
///    receiver has no page origin to resolve against, so it gets
///    `castProxyBase + <encoded url>` — the same base the server hands the
///    browser sender — and every child manifest/segment stays looped through
///    the proxy.
/// The shared Streamio CAF receiver, registered in the Google Cast console
/// against the static deployment in the `cast-receiver` repo.
///
/// Safe as a hardcoded default because that deployment is **install-agnostic**:
/// it is handed `apiBase`/`castProxyBase` in `customData` on every LOAD, so one
/// receiver serves every hosting point. Only an install that deliberately runs
/// its own receiver needs a different id, and that arrives from the server.
///
/// Kept in sync with `CAST_RECEIVER_APP_ID`'s default in the backend's
/// `routes/content.router.ts` and with `NSBonjourServices` in `Info.plist` —
/// iOS lists receiver ids literally, so discovery misses an id that isn't there.
const String kStreamioReceiverAppId = 'BF64D6B2';

/// The one spelling of the HLS content type a LOAD may carry — **lowercase**.
///
/// CAF picks its playback pipeline by looking this string up in its own table
/// and the lookup is case-sensitive. The widely copied `application/x-mpegURL`
/// spelling misses it, so the manifest goes to the plain media element, which
/// cannot play a playlist: the load dies ~13s later as error 100
/// (`MEDIA_UNKNOWN`) and poisons that receiver page for every later load, so
/// the receiver's recovery ladder burns all three attempts on a stream that is
/// perfectly healthy. The browser sender always sent the lowercase form, which
/// is why the same title cast fine from a browser and failed from here.
///
/// The receiver canonicalizes whatever it is handed (`normalizeLoad()` in the
/// `cast-receiver` repo), so this is belt and braces — but a receiver
/// deployment can be older than this app, so the sender must be right too.
const String kCastHlsContentType = 'application/x-mpegurl';

/// Progressive sources (some resolve to an MP4 rather than HLS). Lowercase
/// for the same reason as [kCastHlsContentType].
const String kCastProgressiveContentType = 'video/mp4';

/// The content type for a LOAD. The only place either constant is chosen, so
/// the two senders and the receiver can't drift on it.
String castContentTypeFor({required bool progressive}) =>
    progressive ? kCastProgressiveContentType : kCastHlsContentType;

class CastService {
  CastService(this._content);

  final ContentApi _content;

  CastConfigInfo? _config;
  bool _initialized = false;

  /// The id the platform SDK was actually handed, which is **not** necessarily
  /// [CastConfigInfo.appId] after the override is edited mid-session: the Cast
  /// SDK builds its shared instance once per process and ignores options
  /// afterwards. The settings screen compares the two to decide whether to ask
  /// for a restart.
  String? _liveAppId;
  String? get liveAppId => _liveAppId;

  /// Why the last [initialize] failed, for the settings screen to show.
  /// Null when Cast is fine or has not been tried.
  String? _lastError;
  String? get lastError => _lastError;

  /// Cast is Android/iOS only — the plugin has no desktop implementation, and
  /// the button is hidden everywhere else.
  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  bool get hasSession =>
      isSupported && GoogleCastSessionManager.instance.hasConnectedSession;

  Stream<GoogleCastSession?> get sessionStream =>
      GoogleCastSessionManager.instance.currentSessionStream;

  Stream<List<GoogleCastDevice>> get devicesStream =>
      GoogleCastDiscoveryManager.instance.devicesStream;

  /// Current configuration, once [initialize] has run.
  CastConfigInfo? get config => _config;

  /// Resolves the receiver id and hands it to the platform SDK. Safe to call
  /// repeatedly; only the first successful call does the work.
  ///
  /// A failure to reach `/api/cast-config` is **not** fatal: an old deployment
  /// that 404s the endpoint, or a server that's briefly unreachable, still
  /// leaves a usable receiver id (the local override, or the default media
  /// receiver) and a working Cast button. Only the platform SDK refusing to
  /// initialize disables Cast — and that failure is now reported instead of
  /// swallowed, because the symptom otherwise is a button that never appears
  /// with nothing anywhere saying why.
  Future<bool> initialize() async {
    if (!isSupported) {
      _lastError = 'Casting is only available on Android and iOS.';
      return false;
    }
    if (_initialized) return true;

    final override = await _readOverride();

    CastConfig? remote;
    String? remoteError;
    try {
      remote = await _content.castConfig();
    } catch (err) {
      remoteError = 'Could not read /api/cast-config from the server ($err).';
    }

    final serverAppId = (remote?.castReceiverAppId ?? '').trim();
    final CastAppIdSource source;
    final String appId;
    if (override != null) {
      source = CastAppIdSource.override;
      appId = override;
    } else if (serverAppId.isNotEmpty) {
      source = CastAppIdSource.server;
      appId = serverAppId;
    } else {
      source = CastAppIdSource.fallback;
      appId = kStreamioReceiverAppId;
    }

    _config = CastConfigInfo(
      appId: appId,
      source: source,
      proxyBase: _resolveProxyBase(remote?.castProxyBase),
      serverAppId: serverAppId.isEmpty ? null : serverAppId,
    );

    try {
      final GoogleCastOptions options = Platform.isIOS
          ? IOSGoogleCastOptions(
              GoogleCastDiscoveryCriteriaInitialize.initWithApplicationID(appId),
            )
          : GoogleCastOptionsAndroid(appId: appId);

      await GoogleCastContext.instance.setSharedInstanceWithOptions(options);
      _initialized = true;
      _liveAppId = appId;
      _lastError = remoteError;
      return true;
    } catch (err) {
      // Google Play services missing, or the Cast SDK's OptionsProvider
      // meta-data absent from the manifest. Either way Cast is unusable and
      // the caller hides the button.
      _lastError = 'The Cast SDK failed to start: $err';
      return false;
    }
  }

  /// The prefix every cast URL is built on.
  ///
  /// `GET /api/cast-config` is the authority — it serves `CAST_PROXY_PREFIX`,
  /// derived from the install's own `APP_URL`, which is the one base a
  /// Chromecast can be sure of reaching. But that call is allowed to fail
  /// ([initialize] treats it as non-fatal), and an empty base used to mean the
  /// **raw** upstream URL went to the receiver: a CDN fetched from a
  /// Chromecast's own IP with no Referer is a 403, i.e. a cast that connects
  /// and then dies with a media error. Deriving the conventional prefix from
  /// the server this client is already talking to is a far better guess than
  /// that — it is the same fallback the receiver applies to an `apiBase` that
  /// arrives without a `castProxyBase`, and it is only wrong for an install
  /// whose public address differs from the one typed at /setup.
  String _resolveProxyBase(String? fromServer) {
    final base = (fromServer ?? '').trim();
    if (base.isNotEmpty) return base;
    final api = _content.baseUrl.replaceAll(RegExp(r'/+$'), '');
    return api.isEmpty ? '' : '$api/api/cast-proxy?url=';
  }

  Future<String?> _readOverride() async {
    try {
      return await CastReceiverConfig.read();
    } catch (_) {
      return null;
    }
  }

  Future<void> startDiscovery() async {
    if (!_initialized) return;
    await GoogleCastDiscoveryManager.instance.startDiscovery();
  }

  Future<void> stopDiscovery() async {
    if (!_initialized) return;
    await GoogleCastDiscoveryManager.instance.stopDiscovery();
  }

  Future<bool> connect(GoogleCastDevice device) =>
      GoogleCastSessionManager.instance.startSessionWithDevice(device);

  Future<void> disconnect() async {
    _lastLoad = null;
    _lastMediaInfo = null;
    await GoogleCastSessionManager.instance.endSessionAndStopCasting();
  }

  /// What this app last handed a receiver, and the panel's last-resort source
  /// for the things the transport cannot tell it.
  ///
  /// **This is not belt-and-braces; on Android it is the only source of a
  /// duration.** Two independent holes in the plugin's Android bridge meet
  /// here: `GoogleCastMediaInfo.fromMap` builds the `MediaInfo` without ever
  /// calling `setStreamDuration`, so the duration passed to [load] is dropped
  /// before it reaches the receiver, and what comes back in the media status
  /// arrives only if the receiver worked one out for itself. With a receiver
  /// that also isn't answering on the control channel — an older build cached
  /// on the device, a native bridge that didn't attach — the panel had no
  /// duration at all, which is a progress bar that cannot be dragged and reads
  /// `00:00` on the right.
  ///
  /// Cleared on [disconnect] so a new session never inherits the last one's
  /// numbers. It can still go stale *within* a session — the receiver advances
  /// episodes by itself — so it is consulted last, behind both `STATE` and the
  /// media status, either of which corrects it the moment they arrive.
  CastLoad? _lastLoad;
  CastLoad? get lastLoad => _lastLoad;

  /// The proxy prefix with a [referer] override folded in, ready for an
  /// encoded target to be appended.
  ///
  /// A resolver that attached a `Referer` to the stream did so because the CDN
  /// demands that exact value and 403s anything else. `/api/cast-proxy` takes
  /// it as `ref=`, and
  /// threads it into the child prefix it rewrites every nested manifest URI
  /// with, so passing it here covers the segments as well as the playlist.
  /// Omitting it is what makes a title play in the browser (whose sender does
  /// fold it in — `castProxyUrl()` in `../web/public/scripts/watch.js`) and
  /// fail from the app.
  ///
  /// The base ends in `url=`; the extra parameter goes in ahead of it.
  String castProxyBase({String referer = ''}) {
    final base = _config?.proxyBase ?? '';
    if (base.isEmpty || referer.isEmpty) return base;
    return base.replaceFirst(
      RegExp(r'url=$'),
      'ref=${Uri.encodeComponent(referer)}&url=',
    );
  }

  /// Absolute, proxied URL for the receiver. Falls back to the raw URL if
  /// there is no proxy base at all — see [_resolveProxyBase] for how unlikely
  /// that now is.
  String receiverUrl(String rawUrl, {String referer = ''}) {
    final base = castProxyBase(referer: referer);
    if (base.isEmpty) return rawUrl;
    return '$base${Uri.encodeComponent(rawUrl)}';
  }

  /// Hands a stream to the connected receiver.
  ///
  /// [payload] carries the `customData` contract the Streamio receiver reads —
  /// see [CastPayload]. It is optional: without it the receiver still plays,
  /// using only the media metadata, but loses artwork, autoplay-next and
  /// recovery from an expired stream URL. Passing it is strongly preferred.
  Future<void> load({
    required String rawUrl,
    required String title,
    String? subtitle,
    String? posterUrl,
    Duration startFrom = Duration.zero,
    CastPayload? payload,
    Duration? duration,
    bool progressive = false,
    String referer = '',
  }) async {
    final customData = payload?.toJson();
    final tracks = _subtitleTracks(payload);
    final defaultTrack = _defaultTrackId(payload);
    final url = receiverUrl(rawUrl, referer: referer);

    final media = GoogleCastMediaInformation(
      // **The proxied URL, in `contentId` as well as `contentUrl`.** CAF
      // plays whichever of the two is set, but the receiver's LOAD
      // interceptor reads `contentId` first (`normalizeLoad()` in the
      // `cast-receiver` repo) and sniffs the container format off it, so a
      // raw upstream URL there had it deciding what to play from one string
      // while playing another. The browser sender and the receiver's own
      // self-issued loads both set the proxied URL in both fields; this now
      // matches them.
      contentId: url,
      // "buffered", not "live": these are VOD streams with a known duration,
      // and marking them live disables seeking on the receiver.
      streamType: CastMediaStreamType.buffered,
      contentUrl: Uri.parse(url),
      // Some sources resolve to a progressive MP4 rather than HLS, and
      // declaring that as HLS makes the receiver fail to parse it.
      //
      // Lowercase, always — see [kCastHlsContentType] for what a capital
      // letter here costs.
      contentType: castContentTypeFor(progressive: progressive),
      metadata: _metadata(
        payload: payload,
        title: title,
        subtitle: subtitle,
        posterUrl: posterUrl,
      ),
      duration: duration,
      tracks: tracks.isEmpty ? null : tracks,
      // Demuxed streams (separate audio and video renditions) can't be
      // auto-detected by the receiver and otherwise fail
      // with error 315 (HLS_SEGMENT_PARSING). The receiver sets these too; both
      // do it so the hint still ships if either side is an older build.
      hlsSegmentFormat: progressive ? null : CastHlsSegmentFormat.ts,
      hlsVideoSegmentFormat:
          progressive ? null : HlsVideoSegmentFormat.mpeg2Ts,
      customData: customData,
    );

    await GoogleCastRemoteMediaClient.instance.loadMedia(
      media,
      autoPlay: true,
      playPosition: startFrom,
      activeTrackIds: defaultTrack == null ? null : [defaultTrack],
      customData: customData,
    );

    _lastLoad = CastLoad(
      title: title,
      subtitle: subtitle,
      duration: duration ??
          (payload?.durationSeconds != null && payload!.durationSeconds! > 0
              ? Duration(seconds: payload.durationSeconds!)
              : null),
      payload: payload,
    );
  }

  /// Assistant ("what's playing") and the phone's media notification read
  /// `MediaInformation.metadata`, **not** the receiver's DOM — so this stays
  /// populated even though the receiver draws its own UI from [CastPayload].
  GoogleCastMediaMetadata _metadata({
    required CastPayload? payload,
    required String title,
    String? subtitle,
    String? posterUrl,
  }) {
    final art = payload?.poster.isNotEmpty == true ? payload!.poster : posterUrl;
    final images = [
      if (art != null && art.isNotEmpty) GoogleCastImage(url: Uri.parse(art)),
    ];

    if (payload != null && payload.contentType == 'episode') {
      return GoogleCastTvShowMediaMetadata(
        seriesTitle: payload.showTitle.isEmpty ? title : payload.showTitle,
        season: payload.seasonNumber,
        episode: payload.episodeNumber,
        images: images,
      );
    }

    return GoogleCastMovieMediaMetadata(
      title: payload?.showTitle.isNotEmpty == true ? payload!.showTitle : title,
      subtitle: subtitle,
      images: images,
    );
  }

  List<GoogleCastMediaTrack> _subtitleTracks(CastPayload? payload) {
    final subs = payload?.subtitles ?? const [];
    return [
      for (var i = 0; i < subs.length; i++)
        GoogleCastMediaTrack(
          // Track ids must be unique positive integers; 0 is not a valid
          // activeTrackId.
          trackId: i + 1,
          type: TrackType.text,
          subtype: TextTrackType.subtitles,
          trackContentId: subs[i].url,
          trackContentType: 'text/vtt',
          name: subs[i].label,
          language: _language(subs[i].lang),
        ),
    ];
  }

  int? _defaultTrackId(CastPayload? payload) {
    final subs = payload?.subtitles ?? const [];
    for (var i = 0; i < subs.length; i++) {
      if (subs[i].isDefault) return i + 1;
    }
    return null;
  }

  /// The plugin types track languages as an [Rfc5646Language] enum, while
  /// providers hand back free-form codes. Match on the code and give up
  /// quietly — the language is a label, not something playback depends on.
  Rfc5646Language? _language(String code) {
    if (code.isEmpty) return null;
    final wanted = code.toLowerCase();
    for (final language in Rfc5646Language.values) {
      if (language.value.toLowerCase() == wanted) return language;
    }
    // "ita" / "eng": ISO 639-2, which this enum doesn't carry. Fall back to the
    // two-letter prefix so the common case still labels correctly.
    final short = wanted.length > 2 ? wanted.substring(0, 2) : wanted;
    for (final language in Rfc5646Language.values) {
      if (language.value.toLowerCase() == short) return language;
    }
    return null;
  }

  // ── Transport: the standard Cast media channel ──────────────────────────
  //
  // These are plain CAF media commands and need no receiver support: the
  // receiver installs no interceptor for any of them (it only intercepts
  // LOAD) and advertises SEEK/PAUSE in `supportedCommands`, so CAF services
  // them natively. That also means they keep working against a Chromecast
  // running a receiver older than this build.

  Future<void> play() => GoogleCastRemoteMediaClient.instance.play();
  Future<void> pause() => GoogleCastRemoteMediaClient.instance.pause();
  Future<void> stop() => GoogleCastRemoteMediaClient.instance.stop();

  Future<void> playOrPause({required bool isPlaying}) =>
      isPlaying ? pause() : play();

  /// Skip by [offset]; negative rewinds. The ±10s buttons.
  ///
  /// **Resolved to an absolute position here rather than sent as a relative
  /// seek, because `relative` does not survive the trip on Android.** The
  /// plugin's `GoogleCastSeekOptionsBuilder.fromMap` reads `position`,
  /// `resumeState` and `seekToInfinity` and never looks at `relative`, so a
  /// +10s skip arrived at the receiver as `MediaSeekOptions.setPosition(10s)`
  /// — an absolute seek to ten seconds in. That is exactly the reported
  /// symptom: "forward 10" jumped back to 0:10 from anywhere in the film, and
  /// "back 10" pinned playback to the start. iOS honours the flag, so the bug
  /// was Android-only and invisible in the plugin's own tests.
  ///
  /// Computing the target locally is accurate because [playerPosition] is fed
  /// by the media channel's progress listener — every 500ms on Android, every
  /// second on iOS — not by the receiver's 5s `STATE` broadcast. Callers that
  /// already have a fresher position on screen (the panel, mid-scrub) pass it
  /// as [from].
  Future<void> seekBy(
    Duration offset, {
    Duration? from,
    Duration? duration,
  }) {
    return seekTo(resolveSeekTarget(
      from: from ?? playerPosition,
      offset: offset,
      duration: duration,
    ));
  }

  /// Where a [offset] skip from [from] lands, clamped into the stream.
  ///
  /// Pure, and separated out so the arithmetic is testable without a Cast
  /// session. Seeking to exactly [duration] ends playback (the receiver treats
  /// it as reaching the end and advances or idles), so a forward skip past the
  /// end stops [_endGuard] short of it instead.
  static Duration resolveSeekTarget({
    required Duration from,
    required Duration offset,
    Duration? duration,
  }) {
    var target = from + offset;
    if (target < Duration.zero) target = Duration.zero;
    if (duration != null && duration > Duration.zero) {
      final ceiling = duration > _endGuard ? duration - _endGuard : Duration.zero;
      if (target > ceiling) target = ceiling;
    }
    return target;
  }

  static const Duration _endGuard = Duration(seconds: 2);

  /// Absolute seek, for the progress bar.
  Future<void> seekTo(Duration position) {
    return GoogleCastRemoteMediaClient.instance.seek(
      GoogleCastMediaSeekOption(
        position: position < Duration.zero ? Duration.zero : position,
      ),
    );
  }

  /// Device volume, 0..1. There is no mute command in the plugin, so the panel
  /// mutes by driving this to zero and remembering what to restore.
  Future<void> setVolume(double level) async {
    GoogleCastSessionManager.instance.setDeviceVolume(level.clamp(0.0, 1.0));
  }

  /// Playback status from the media channel: player state, volume, active
  /// track ids. Independent of the Streamio `STATE` broadcast, and available
  /// even when the control channel isn't.
  ///
  /// Passed through [_remember] on the way out, because **the plugin replaces
  /// the whole status on every update and the receiver does not repeat
  /// `media` in every one of them.** A status carrying only a player-state
  /// change therefore arrives with `mediaInformation: null`, and anything read
  /// straight off the stream — the duration, the metadata — blinks out of
  /// existence until a status that does carry it comes along. That is what a
  /// progress bar showing `00:00` over a running stream actually was.
  Stream<GoggleCastMediaStatus?> get mediaStatusStream =>
      GoogleCastRemoteMediaClient.instance.mediaStatusStream.map(_remember);

  GoogleCastMediaInformation? _lastMediaInfo;

  /// The last media info any status carried, which stays true for as long as
  /// the receiver is playing the same thing — and is replaced when it isn't,
  /// including after the receiver advances an episode on its own.
  GoogleCastMediaInformation? get lastMediaInfo => _lastMediaInfo;

  GoggleCastMediaStatus? _remember(GoggleCastMediaStatus? status) {
    final info = status?.mediaInformation;
    if (info != null) _lastMediaInfo = info;
    return status;
  }

  GoggleCastMediaStatus? get mediaStatus =>
      GoogleCastRemoteMediaClient.instance.mediaStatus;

  /// Position, updated far more often than the 5s `STATE` broadcast — this is
  /// what the panel's progress bar runs on.
  Stream<Duration> get positionStream =>
      GoogleCastRemoteMediaClient.instance.playerPositionStream;

  /// The latest position the media channel reported, readable synchronously.
  /// Backed by the plugin's `BehaviorSubject`, so it is the last value the
  /// progress listener pushed rather than a fresh query — good to half a
  /// second, which is what [seekBy] needs.
  Duration get playerPosition =>
      GoogleCastRemoteMediaClient.instance.playerPosition;

  // ── Content: the Streamio control channel ───────────────────────────────
  //
  // Everything below needs the custom namespace, and therefore the native
  // bridge in [CastControlChannel] — flutter_chrome_cast has no API for it.
  // All of it is advisory: a receiver that predates a message ignores it.

  /// Receiver `STATE` messages. Other message types are filtered out; use
  /// [controlMessages] for those.
  Stream<CastState> get stateStream => controlMessages
      .where((message) => message['type'] == 'STATE')
      .map(CastState.fromJson);

  /// Every message from the receiver, undecoded beyond JSON.
  Stream<Map<String, dynamic>> get controlMessages =>
      CastControlChannel.instance.messages;

  /// Asks the receiver for a `STATE` immediately, rather than waiting up to 5s
  /// for the next broadcast. Send it as soon as a session connects.
  Future<void> hello() =>
      CastControlChannel.instance.send({'type': 'HELLO', 'v': 1});

  /// [trackId] <= 0 clears all text tracks.
  ///
  /// This goes over the control channel rather than through
  /// `setActiveTrackIDs` because the receiver's `TextTracksManager` is the
  /// authority on what is active — it is what `STATE.activeTrackId` reports
  /// back, so driving it any other way would let the panel and the receiver
  /// disagree. Same choice the web sender makes.
  Future<void> setSubtitle(int trackId) =>
      CastControlChannel.instance.send({'type': 'SET_SUBTITLE', 'trackId': trackId});

  /// Switch the audio rendition, by receiver track id or by language.
  ///
  /// A no-op when the device can't enumerate the manifest's audio tracks —
  /// see [CastState.audioTracks], which is empty in exactly that case and is
  /// what the panel uses to decide whether to offer the control at all.
  Future<void> setAudioTrack({int? trackId, String? language}) {
    return CastControlChannel.instance.send({
      'type': 'SET_AUDIO_TRACK',
      if (trackId != null) 'trackId': trackId,
      if (language != null && language.isNotEmpty) 'language': language,
    });
  }

  /// Jump to an episode in the queue the receiver holds — the one sent in
  /// `customData.episodes`, so the indices are the same ones [CastPayload]
  /// was built from.
  Future<void> playEpisodeAt(int index, {Duration? startFrom}) {
    return CastControlChannel.instance.send({
      'type': 'PLAY_EPISODE',
      'index': index,
      if (startFrom != null) 'positionSeconds': startFrom.inSeconds,
    });
  }

  /// Fires an armed up-next immediately, or resolves the next episode.
  Future<void> playNextNow() =>
      CastControlChannel.instance.send({'type': 'PLAY_NEXT_NOW'});

  Future<void> setAutoplay(bool enabled) => CastControlChannel.instance
      .send({'type': 'SET_AUTOPLAY', 'enabled': enabled});

  /// Runs the receiver's own Skip Intro/Recap/Credits/Preview action if a
  /// segment is currently active (`CastState.skipSegment`); a no-op
  /// otherwise. See `docs/protocol.md` §5 in the `cast-receiver` repo.
  Future<void> skipSegmentNow() =>
      CastControlChannel.instance.send({'type': 'SKIP_SEGMENT_NOW'});
}

/// Where the receiver id in use came from.
enum CastAppIdSource {
  /// Typed into Settings on this device; wins over everything.
  override,

  /// `castReceiverAppId` from `GET /api/cast-config`.
  server,

  /// [kStreamioReceiverAppId] — the shared Streamio receiver, used when the
  /// server couldn't be asked. It is install-independent (the receiver is told
  /// which backend to talk to per cast), so it is a correct answer here rather
  /// than a degraded one.
  fallback,
}

class CastConfigInfo {
  const CastConfigInfo({
    required this.appId,
    required this.source,
    required this.proxyBase,
    this.serverAppId,
  });

  /// The id actually used for discovery and session launch.
  final String appId;

  final CastAppIdSource source;

  /// e.g. `https://host/api/cast-proxy?url=` — already includes the trailing
  /// `url=`, so an encoded target is appended directly. Empty when the server
  /// didn't answer, in which case the raw stream URL is cast unproxied.
  final String proxyBase;

  /// What the server reported, kept even when an override supersedes it so the
  /// settings screen can show both.
  final String? serverAppId;
}


/// A snapshot of the last [CastService.load], kept so the cast panel can name
/// and scale what is playing when neither the receiver's `STATE` nor the media
/// status will. See [CastService.lastLoad] for why that is a normal state on
/// Android rather than an edge case.
class CastLoad {
  const CastLoad({
    required this.title,
    this.subtitle,
    this.duration,
    this.payload,
  });

  final String title;
  final String? subtitle;
  final Duration? duration;

  /// The `customData` that went with it — the show title, episode label and
  /// the flattened queue, all of which the panel can render.
  final CastPayload? payload;

  /// What to show as the panel's heading. The payload's show title is the
  /// better of the two (it is the show, not the episode), with the load's
  /// plain title behind it.
  String get displayTitle {
    final show = payload?.showTitle ?? '';
    return show.isNotEmpty ? show : title;
  }

  /// The line under it: episode identity when there is one.
  String get displaySubtitle {
    final label = payload?.episodeLabel ?? '';
    final episodeTitle = payload?.episodeTitle ?? '';
    final parts = [
      if (label.isNotEmpty) label,
      if (isReadableTitle(episodeTitle)) episodeTitle,
    ];
    if (parts.isNotEmpty) return parts.join(' · ');
    return subtitle ?? '';
  }

  /// Whether an episode title is worth showing a human.
  ///
  /// Several providers hand back the release name of the file rather than a
  /// title — `2.5.Dimensional.Seduction.-.…S01E01.La.nuova.iscritta…1080p.
  /// AMZN.WEB-DL.JPN.AAC2.0.H.264` — which in a one-line header is a wall of
  /// dots that pushes the part that identifies the episode off the end. A
  /// title with no spaces at all is one of those; a real one always has some.
  static bool isReadableTitle(String title) =>
      title.isNotEmpty && title.contains(' ');

  bool get isEpisode => (payload?.contentType ?? '') == 'episode';

  List<CastEpisodeRef> get episodes => payload?.episodes ?? const [];
}
