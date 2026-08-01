import '../../core/api/content_api.dart';
import '../../core/models/models.dart';

/// Resolves a playable stream: fetch the server list, then resolve one of
/// them. Deliberately *not* a Riverpod provider — a resolved [PlaybackSource]
/// is signed and expires in minutes, so it must never be cached. Every
/// playback attempt re-resolves.
Future<({List<VideoServer> servers, PlaybackSource source, int serverIndex})>
    resolvePlayback(
  ContentApi api,
  String provider,
  String contentId, {
  String contentType = 'episode',
  List<VideoServer>? knownServers,
  int serverIndex = 0,
}) async {
  final servers = knownServers ??
      await api.servers(contentId, provider: provider, contentType: contentType);

  if (servers.isEmpty) {
    throw StateError('No servers available for this title.');
  }

  final index = serverIndex.clamp(0, servers.length - 1);
  final source = await api.resolveVideo(
    contentId,
    servers[index],
    provider: provider,
    contentType: contentType,
  );

  return (servers: servers, source: source, serverIndex: index);
}

/// Port of `needsSourceProxy()` / `proxyInsecureSource()` in
/// `web/public/scripts/watch.js`.
///
/// vixcloud.co is always routed through the server's proxy: fetched directly,
/// its CDN sees whatever Referer/Origin this client happens to send and
/// intermittently 403s depending on the edge node it lands on. Going through
/// `/api/cast-proxy` makes the server fetch it with a fixed, known-good
/// Referer/User-Agent, for the playlist and every child manifest and segment
/// it rewrites.
bool needsSourceProxy(String url) {
  if (url.startsWith('http://')) return true;
  final host = Uri.tryParse(url)?.host ?? '';
  return RegExp(r'(^|\.)vixcloud\.co$', caseSensitive: false).hasMatch(host);
}

String proxiedSourceUrl(String url, String serverBaseUrl) {
  if (!needsSourceProxy(url)) return url;
  return '$serverBaseUrl/api/cast-proxy?direct=1&url=${Uri.encodeComponent(url)}';
}
