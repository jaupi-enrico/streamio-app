import 'dart:io';

import 'package:flutter_chrome_cast/cast_context.dart';
import 'package:flutter_chrome_cast/common.dart';
import 'package:flutter_chrome_cast/discovery.dart';
import 'package:flutter_chrome_cast/entities.dart';
import 'package:flutter_chrome_cast/media.dart';
import 'package:flutter_chrome_cast/models.dart';
import 'package:flutter_chrome_cast/session.dart';

import '../api/content_api.dart';
import '../config/cast_receiver_config.dart';
import '../models/models.dart';

/// Chromecast sender.
///
/// Two details here are specific to Streamio rather than to Cast in general:
///
///  * **The receiver app id is resolved, not constant.** The deployment runs a
///    custom CAF receiver (`redirect/cast-receiver.html`) because the default
///    media receiver mishandles the demuxed audio/video HLS these providers
///    emit. The id normally comes from the server (`GET /api/cast-config`,
///    serving `CAST_RECEIVER_APP_ID`), but a device-local override wins over
///    it — see [CastReceiverConfig] for why that has to exist.
///  * **The URL sent to the receiver must be absolute and proxied.** The
///    receiver has no page origin to resolve against, so it gets
///    `castProxyBase + <encoded url>` — the same base the server hands the
///    browser sender — and every child manifest/segment stays looped through
///    the proxy.
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
      appId = GoogleCastDiscoveryCriteria.kDefaultApplicationId;
    }

    _config = CastConfigInfo(
      appId: appId,
      source: source,
      proxyBase: remote?.castProxyBase ?? '',
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
    await GoogleCastSessionManager.instance.endSessionAndStopCasting();
  }

  /// Absolute, proxied URL for the receiver. Falls back to the raw URL if the
  /// server didn't give a proxy base.
  String receiverUrl(String rawUrl) {
    final base = _config?.proxyBase;
    if (base == null || base.isEmpty) return rawUrl;
    return '$base${Uri.encodeComponent(rawUrl)}';
  }

  Future<void> load({
    required String rawUrl,
    required String title,
    String? subtitle,
    String? posterUrl,
    Duration startFrom = Duration.zero,
  }) async {
    final media = GoogleCastMediaInformation(
      contentId: rawUrl,
      // "buffered", not "live": these are VOD streams with a known duration,
      // and marking them live disables seeking on the receiver.
      streamType: CastMediaStreamType.buffered,
      contentUrl: Uri.parse(receiverUrl(rawUrl)),
      contentType: 'application/x-mpegURL',
      metadata: GoogleCastMovieMediaMetadata(
        title: title,
        subtitle: subtitle,
        images: [
          if (posterUrl != null) GoogleCastImage(url: Uri.parse(posterUrl)),
        ],
      ),
    );

    await GoogleCastRemoteMediaClient.instance.loadMedia(
      media,
      autoPlay: true,
      playPosition: startFrom,
    );
  }

  Future<void> play() => GoogleCastRemoteMediaClient.instance.play();
  Future<void> pause() => GoogleCastRemoteMediaClient.instance.pause();
  Future<void> stop() => GoogleCastRemoteMediaClient.instance.stop();
}

/// Where the receiver id in use came from.
enum CastAppIdSource {
  /// Typed into Settings on this device; wins over everything.
  override,

  /// `castReceiverAppId` from `GET /api/cast-config`.
  server,

  /// Google's default media receiver, used when neither of the above is
  /// available. It plays plain HLS but mishandles the demuxed audio/video
  /// these providers emit, so it is a last resort, not a good default.
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
