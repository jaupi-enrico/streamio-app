import '../../core/api/content_api.dart';
import '../../core/models/models.dart';

/// Resolves a playable stream: fetch the server list, then resolve one of
/// them. Deliberately *not* a Riverpod provider — a resolved [PlaybackSource]
/// is signed and expires in minutes, so it must never be cached. Every
/// playback attempt re-resolves.
///
/// [fresh] bypasses the *server's* resolve cache too, and belongs only to a
/// retry after a failure — see [ContentApi.resolveVideo].
Future<({List<VideoServer> servers, PlaybackSource source, int serverIndex})>
    resolvePlayback(
  ContentApi api,
  String provider,
  String contentId, {
  String contentType = 'episode',
  List<VideoServer>? knownServers,
  int serverIndex = 0,
  bool fresh = false,
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
    fresh: fresh,
  );

  return (servers: servers, source: source, serverIndex: index);
}

/// Hostname suffixes that are always routed through the server's proxy, given
/// at build time as a comma-separated list:
/// `--dart-define=STREAMIO_PROXY_HOSTS=cdn.example.net,edge.example.org`.
///
/// **Empty by default**, which makes this client decide exactly like the web
/// player does — on the scheme and on the resolver's headers, below. The knob
/// exists for a CDN that 403s a direct fetch *without* the resolve having
/// asked for any header, which neither rule can see coming; a deployment that
/// hits one pins it at build time instead of carrying a host list in here.
const String _proxyHostsFromEnvironment =
    String.fromEnvironment('STREAMIO_PROXY_HOSTS');

/// Parses the `STREAMIO_PROXY_HOSTS` form: comma-separated, case-insensitive,
/// blanks ignored.
List<String> parseProxyHosts(String value) => value
    .split(',')
    .map((host) => host.trim().toLowerCase())
    .where((host) => host.isNotEmpty)
    .toList(growable: false);

/// What [needsSourceProxy] matches against when it isn't told otherwise.
final List<String> pinnedProxyHosts =
    parseProxyHosts(_proxyHostsFromEnvironment);

/// Port of `needsSourceProxy()` / `proxyInsecureSource()` in
/// `web/public/scripts/watch.js`.
///
/// Going through `/api/cast-proxy` makes the server do the fetch with a fixed,
/// known-good Referer/User-Agent, for the playlist and every child manifest
/// and segment it rewrites — the answer for a CDN that 403s depending on which
/// edge node the request lands on.
///
/// [headers] is the resolved source's own header map: a resolver attaching
/// headers to a stream means the upstream demands a `Referer`/`Origin` the
/// client cannot set on the request itself, and their presence *is* the
/// signal to proxy. That is what covers a source whose CDN hostnames are
/// generated fresh per resolve and so could never be matched by a host list.
///
/// [pinnedHosts] defaults to [pinnedProxyHosts]; a suffix match, so
/// `example.net` covers `cdn.example.net` too.
bool needsSourceProxy(
  String url, {
  Map<String, String> headers = const {},
  List<String>? pinnedHosts,
}) {
  if (url.startsWith('http://')) return true;
  if (headers.isNotEmpty) return true;
  final host = (Uri.tryParse(url)?.host ?? '').toLowerCase();
  if (host.isEmpty) return false;
  return (pinnedHosts ?? pinnedProxyHosts)
      .any((pinned) => host == pinned || host.endsWith('.$pinned'));
}

String proxiedSourceUrl(
  String url,
  String serverBaseUrl, {
  Map<String, String> headers = const {},
  List<String>? pinnedHosts,
}) {
  if (!needsSourceProxy(url, headers: headers, pinnedHosts: pinnedHosts)) {
    return url;
  }
  final referer = refererOf(headers);
  final ref = referer.isEmpty ? '' : 'ref=${Uri.encodeComponent(referer)}&';
  return '$serverBaseUrl/api/cast-proxy?direct=1&$ref'
      'url=${Uri.encodeComponent(url)}';
}

/// The `Referer` a resolver asked for, in whatever case it spelled it.
///
/// The proxy's default Referer is the media host's own origin, which some
/// CDNs refuse outright, 403ing anything but the player host that asked for
/// it. Passing it as `ref=` is the only way to reach those, and the
/// server threads it into the prefix it rewrites child manifest URIs with, so
/// it covers the segments too and not just the playlist. Port of
/// `readRefererHeader()` in `../web/public/scripts/watch.js`.
String refererOf(Map<String, String> headers) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == 'referer' &&
        RegExp(r'^https?://', caseSensitive: false).hasMatch(entry.value)) {
      return entry.value;
    }
  }
  return '';
}
