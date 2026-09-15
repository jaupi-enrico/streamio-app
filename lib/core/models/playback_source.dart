import 'video.dart';

/// A resolved, playable stream — what `POST /api/episodes/:id/video` comes
/// back as, once flattened by `core/api/json_mappers.dart`. The backend's
/// `Video` is looser than this (it carries `source`, `playlistUrl` and a
/// `data:`-wrapped manifest that mean overlapping things); this is the one
/// shape the player and the downloader both consume.
///
/// [url] is a directly-playable URL. When the backend returned the manifest
/// inline instead, it lands in [inlineManifest] and the caller materializes
/// it — libmpv can't open a `data:` URI.
///
/// Resolved sources are short-lived (the CDN's tokens expire in minutes) and
/// must never be persisted or cached beyond the current playback attempt.
class PlaybackSource {
  const PlaybackSource({
    required this.url,
    this.inlineManifest,
    this.headers = const {},
    this.subtitles = const [],
    this.type = 'hls',
  });

  factory PlaybackSource.direct(String url, {Map<String, String>? headers}) {
    return PlaybackSource(url: url, headers: headers ?? const {});
  }

  final String url;
  final String? inlineManifest;
  final Map<String, String> headers;
  final List<Subtitle> subtitles;
  final String type;

  PlaybackSource copyWith({
    String? url,
    String? inlineManifest,
    Map<String, String>? headers,
    List<Subtitle>? subtitles,
    String? type,
  }) {
    return PlaybackSource(
      url: url ?? this.url,
      inlineManifest: inlineManifest ?? this.inlineManifest,
      headers: headers ?? this.headers,
      subtitles: subtitles ?? this.subtitles,
      type: type ?? this.type,
    );
  }
}
