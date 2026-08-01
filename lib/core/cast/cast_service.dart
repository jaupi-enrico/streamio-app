import 'dart:io';

import 'package:flutter_chrome_cast/cast_context.dart';
import 'package:flutter_chrome_cast/common.dart';
import 'package:flutter_chrome_cast/discovery.dart';
import 'package:flutter_chrome_cast/entities.dart';
import 'package:flutter_chrome_cast/media.dart';
import 'package:flutter_chrome_cast/models.dart';
import 'package:flutter_chrome_cast/session.dart';

import '../api/content_api.dart';

/// Chromecast sender.
///
/// Two details here are specific to Streamio rather than to Cast in general:
///
///  * **The receiver app id comes from the server** (`GET /api/cast-config`),
///    not from a constant. The deployment runs a custom CAF receiver
///    (`redirect/cast-receiver.html`) because the default media receiver
///    mishandles the demuxed audio/video HLS these providers emit, and its id
///    is per-deployment via `CAST_RECEIVER_APP_ID`.
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

  /// Cast is Android/iOS only — the plugin has no desktop implementation, and
  /// the button is hidden everywhere else.
  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  bool get hasSession =>
      isSupported && GoogleCastSessionManager.instance.hasConnectedSession;

  Stream<GoogleCastSession?> get sessionStream =>
      GoogleCastSessionManager.instance.currentSessionStream;

  Stream<List<GoogleCastDevice>> get devicesStream =>
      GoogleCastDiscoveryManager.instance.devicesStream;

  /// Fetches the receiver id and hands it to the platform SDK. Safe to call
  /// repeatedly; only the first call does the work.
  Future<bool> initialize() async {
    if (!isSupported) return false;
    if (_initialized) return true;

    try {
      final remote = await _content.castConfig();
      final appId = remote.castReceiverAppId.isNotEmpty
          ? remote.castReceiverAppId
          : GoogleCastDiscoveryCriteria.kDefaultApplicationId;

      _config = CastConfigInfo(
        appId: appId,
        proxyBase: remote.castProxyBase,
      );

      final GoogleCastOptions options = Platform.isIOS
          ? IOSGoogleCastOptions(
              GoogleCastDiscoveryCriteriaInitialize.initWithApplicationID(appId),
            )
          : GoogleCastOptionsAndroid(appId: appId);

      GoogleCastContext.instance.setSharedInstanceWithOptions(options);
      _initialized = true;
      return true;
    } catch (_) {
      // No config (server unreachable, Cast not set up on this deployment):
      // the caller keeps the Cast button hidden.
      return false;
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

class CastConfigInfo {
  const CastConfigInfo({required this.appId, required this.proxyBase});

  final String appId;

  /// e.g. `https://host/api/cast-proxy?url=` — already includes the trailing
  /// `url=`, so an encoded target is appended directly.
  final String proxyBase;
}
