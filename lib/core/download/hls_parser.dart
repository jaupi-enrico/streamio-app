/// Minimal HLS manifest parsing, ported from `parseMaster()` / `parseMedia()`
/// in `web/public/scripts/watch.js`.
///
/// A package would cover the spec more thoroughly, but the shapes that
/// actually have to work here are the ones the web downloader already
/// handles — in particular demuxed output, where the master playlist points
/// at separate `?type=video` and `?type=audio` media
/// playlists via `#EXT-X-MEDIA`, and both have to be fetched and kept.
library;

/// One `#EXT-X-STREAM-INF` entry: a video rendition at a given bitrate.
class HlsVariant {
  const HlsVariant({
    required this.url,
    this.bandwidth = 0,
    this.resolution,
    this.codecs,
    this.audioGroupId,
  });

  final String url;
  final int bandwidth;
  final String? resolution;
  final String? codecs;
  final String? audioGroupId;

  /// "1080p" style label, falling back to the bitrate when the manifest
  /// didn't declare a resolution.
  String get label {
    final res = resolution;
    if (res != null) {
      final height = res.split('x').lastOrNull;
      if (height != null && height.isNotEmpty) return '${height}p';
    }
    if (bandwidth > 0) return '${(bandwidth / 1000000).toStringAsFixed(1)} Mbps';
    return 'Default';
  }
}

/// One `#EXT-X-MEDIA:TYPE=AUDIO` (or SUBTITLES) rendition.
class HlsRendition {
  const HlsRendition({
    required this.type,
    required this.url,
    this.groupId,
    this.name,
    this.language,
    this.isDefault = false,
  });

  final String type;
  final String url;
  final String? groupId;
  final String? name;
  final String? language;
  final bool isDefault;
}

class HlsMaster {
  const HlsMaster({this.variants = const [], this.renditions = const []});

  final List<HlsVariant> variants;
  final List<HlsRendition> renditions;

  bool get isEmpty => variants.isEmpty && renditions.isEmpty;

  List<HlsRendition> get audioRenditions =>
      renditions.where((r) => r.type == 'AUDIO').toList();

  List<HlsRendition> get subtitleRenditions =>
      renditions.where((r) => r.type == 'SUBTITLES').toList();

  /// Highest-bandwidth variant, i.e. best quality — the default choice when
  /// the user doesn't pick one.
  HlsVariant? get best {
    if (variants.isEmpty) return null;
    final sorted = [...variants]..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
    return sorted.first;
  }

  /// The audio rendition a given variant should be paired with: the one in
  /// its `AUDIO=` group, preferring the group's DEFAULT member.
  HlsRendition? audioFor(HlsVariant variant) {
    final candidates = audioRenditions
        .where((r) => variant.audioGroupId == null || r.groupId == variant.audioGroupId)
        .toList();
    if (candidates.isEmpty) return null;
    return candidates.firstWhere((r) => r.isDefault, orElse: () => candidates.first);
  }
}

/// One `#EXTINF` segment of a media playlist.
class HlsSegment {
  const HlsSegment({
    required this.url,
    required this.durationSeconds,
    this.key,
    this.sequenceNumber = 0,
  });

  final String url;
  final double durationSeconds;

  /// AES-128 key in force for this segment, if the playlist is encrypted.
  final HlsKey? key;

  /// Media sequence number — the AES-128 IV defaults to it when the
  /// `#EXT-X-KEY` line doesn't carry an explicit `IV=`.
  final int sequenceNumber;
}

class HlsKey {
  const HlsKey({required this.method, required this.uri, this.iv});

  final String method;
  final String uri;

  /// Explicit `IV=0x…`, or null to derive it from the sequence number.
  final List<int>? iv;

  bool get isAes128 => method.toUpperCase() == 'AES-128';
}

class HlsMedia {
  const HlsMedia({
    this.segments = const [],
    this.targetDuration = 10,
  });

  final List<HlsSegment> segments;
  final double targetDuration;

  double get totalDuration =>
      segments.fold(0.0, (sum, segment) => sum + segment.durationSeconds);
}

/// Resolves a manifest-relative URI against the playlist it appeared in —
/// the equivalent of `toAbsolute()` in `content.router.ts`'s manifest
/// rewriter, which has to solve the same problem server-side.
String resolveUri(String uri, String baseUrl) {
  if (uri.startsWith('http://') || uri.startsWith('https://')) return uri;

  final base = Uri.parse(baseUrl);
  final origin = '${base.scheme}://${base.host}'
      '${base.hasPort ? ':${base.port}' : ''}';

  // The parent's query is dropped deliberately: a relative URI inherits the
  // directory, never the parent playlist's signing parameters. It's built by
  // hand rather than with Uri.replace(query: '') because that leaves a bare
  // trailing "?" on the result.
  if (uri.startsWith('/')) return '$origin$uri';

  final directory = base.path.replaceAll(RegExp(r'[^/]*$'), '');
  return '$origin$directory$uri';
}

Map<String, String> _parseAttributes(String line) {
  final attributes = <String, String>{};
  // Split on commas that aren't inside quotes (CODECS="a,b" is one value).
  final pattern = RegExp(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)');
  for (final match in pattern.allMatches(line)) {
    final key = match.group(1)!;
    var value = match.group(2) ?? '';
    if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
      value = value.substring(1, value.length - 1);
    }
    attributes[key] = value;
  }
  return attributes;
}

HlsMaster parseMaster(String text, String baseUrl) {
  final variants = <HlsVariant>[];
  final renditions = <HlsRendition>[];
  final lines = text.split('\n');

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();

    if (line.startsWith('#EXT-X-MEDIA:')) {
      final attributes = _parseAttributes(line.substring('#EXT-X-MEDIA:'.length));
      final uri = attributes['URI'];
      // A rendition with no URI is muxed into the video stream — nothing
      // separate to download for it.
      if (uri == null || uri.isEmpty) continue;
      renditions.add(HlsRendition(
        type: attributes['TYPE'] ?? 'AUDIO',
        url: resolveUri(uri, baseUrl),
        groupId: attributes['GROUP-ID'],
        name: attributes['NAME'],
        language: attributes['LANGUAGE'],
        isDefault: (attributes['DEFAULT'] ?? '').toUpperCase() == 'YES',
      ));
      continue;
    }

    if (line.startsWith('#EXT-X-STREAM-INF:')) {
      final attributes =
          _parseAttributes(line.substring('#EXT-X-STREAM-INF:'.length));
      // The URI is the next non-comment line.
      String? uri;
      for (var j = i + 1; j < lines.length; j++) {
        final candidate = lines[j].trim();
        if (candidate.isEmpty || candidate.startsWith('#')) continue;
        uri = candidate;
        i = j;
        break;
      }
      if (uri == null) continue;

      variants.add(HlsVariant(
        url: resolveUri(uri, baseUrl),
        bandwidth: int.tryParse(attributes['BANDWIDTH'] ?? '') ??
            int.tryParse(attributes['AVERAGE-BANDWIDTH'] ?? '') ??
            0,
        resolution: attributes['RESOLUTION'],
        codecs: attributes['CODECS'],
        audioGroupId: attributes['AUDIO'],
      ));
    }
  }

  return HlsMaster(variants: variants, renditions: renditions);
}

/// True when [text] is a master playlist rather than a media playlist.
bool isMasterPlaylist(String text) =>
    text.contains('#EXT-X-STREAM-INF') || text.contains('#EXT-X-MEDIA:');

List<int>? _parseIv(String? value) {
  if (value == null) return null;
  var hex = value.trim();
  if (hex.startsWith('0x') || hex.startsWith('0X')) hex = hex.substring(2);
  if (hex.length != 32) return null;

  final bytes = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    final byte = int.tryParse(hex.substring(i, i + 2), radix: 16);
    if (byte == null) return null;
    bytes.add(byte);
  }
  return bytes;
}

HlsMedia parseMedia(String text, String baseUrl) {
  final segments = <HlsSegment>[];
  var targetDuration = 10.0;
  var duration = 0.0;
  var sequence = 0;
  HlsKey? currentKey;

  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    if (line.startsWith('#EXT-X-TARGETDURATION:')) {
      targetDuration =
          double.tryParse(line.split(':').last.trim()) ?? targetDuration;
      continue;
    }

    if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
      sequence = int.tryParse(line.split(':').last.trim()) ?? 0;
      continue;
    }

    if (line.startsWith('#EXT-X-KEY:')) {
      final attributes = _parseAttributes(line.substring('#EXT-X-KEY:'.length));
      final method = attributes['METHOD'] ?? 'NONE';
      final uri = attributes['URI'];
      // METHOD=NONE ends encryption for the segments that follow.
      currentKey = (method.toUpperCase() == 'NONE' || uri == null || uri.isEmpty)
          ? null
          : HlsKey(
              method: method,
              uri: resolveUri(uri, baseUrl),
              iv: _parseIv(attributes['IV']),
            );
      continue;
    }

    if (line.startsWith('#EXTINF:')) {
      final value = line.substring('#EXTINF:'.length).split(',').first.trim();
      duration = double.tryParse(value) ?? 0;
      continue;
    }

    if (line.startsWith('#')) continue;

    segments.add(HlsSegment(
      url: resolveUri(line, baseUrl),
      durationSeconds: duration,
      key: currentKey,
      sequenceNumber: sequence + segments.length,
    ));
    duration = 0;
  }

  return HlsMedia(segments: segments, targetDuration: targetDuration);
}

/// The AES-128 IV for a segment: the explicit `IV=` when the playlist gave
/// one, otherwise the media sequence number as a 16-byte big-endian value
/// (RFC 8216 §5.2).
List<int> ivForSegment(HlsSegment segment) {
  final explicit = segment.key?.iv;
  if (explicit != null) return explicit;

  final iv = List<int>.filled(16, 0);
  var value = segment.sequenceNumber;
  for (var i = 15; i >= 0 && value > 0; i--) {
    iv[i] = value & 0xFF;
    value >>= 8;
  }
  return iv;
}
