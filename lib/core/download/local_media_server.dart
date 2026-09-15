import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../db/app_database.dart';
import 'segment_store.dart';

/// Serves a downloaded title to the in-app player, decrypting as it goes.
///
/// The stored segments are AES-CTR encrypted (see [SegmentStore]) and there's
/// no on-disk playlist, so there is nothing for a media player to open
/// directly. This binds a plain HTTP server to `127.0.0.1` on an ephemeral
/// port and synthesizes what libmpv expects — a master playlist, one media
/// playlist per track, and segment bodies — decrypting each segment in the
/// response.
///
/// Two things keep it app-only:
///  * it binds to the loopback interface, so nothing off-device can reach it;
///  * every path is prefixed with a random per-launch token, so another app
///    on the same device can't guess a URL either.
///
/// It only runs while something is playing, and stops on [stop].
class LocalMediaServer {
  LocalMediaServer({required AppDatabase database, required SegmentStore store})
      : _db = database,
        _store = store;

  final AppDatabase _db;
  final SegmentStore _store;

  HttpServer? _server;
  String? _token;

  bool get isRunning => _server != null;

  /// Starts the server if it isn't already up and returns the master playlist
  /// URL for [downloadId], ready to hand to the player.
  Future<String> serve(String downloadId) async {
    await start();
    return '$_base/$downloadId/master.m3u8';
  }

  String get _base => 'http://127.0.0.1:${_server!.port}/$_token';

  Future<void> start() async {
    if (_server != null) return;

    final random = Random.secure();
    _token = List<int>.generate(24, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _token = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final segments = request.uri.pathSegments;

      // /<token>/<downloadId>/<resource>
      if (segments.length < 3 || segments.first != _token) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }

      final downloadId = segments[1];
      final resource = segments[2];

      if (resource == 'master.m3u8') {
        await _writeMaster(request, downloadId);
        return;
      }
      if (resource == 'video.m3u8') {
        await _writeMedia(request, downloadId, TrackKind.video);
        return;
      }
      if (resource == 'audio.m3u8') {
        await _writeMedia(request, downloadId, TrackKind.audio);
        return;
      }
      if (resource == 'seg' && segments.length >= 5) {
        await _writeSegment(
          request,
          downloadId,
          segments[3] == 'audio' ? TrackKind.audio : TrackKind.video,
          int.tryParse(segments[4]) ?? 0,
        );
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } catch (_) {
      // A player that hangs up mid-response (seek, close) surfaces here;
      // there's nothing useful to do but drop the connection.
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _writeMaster(HttpRequest request, String downloadId) async {
    final kinds = await _db.trackKinds(downloadId);
    final hasAudio = kinds.contains(TrackKind.audio);

    final buffer = StringBuffer()
      ..writeln('#EXTM3U')
      ..writeln('#EXT-X-VERSION:3');

    if (hasAudio) {
      // Demuxed audio: declare it as a rendition group and point the video
      // variant at it, which is how the source manifest had it too.
      buffer.writeln('#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Audio",'
          'DEFAULT=YES,AUTOSELECT=YES,URI="audio.m3u8"');
      buffer.writeln('#EXT-X-STREAM-INF:BANDWIDTH=4000000,AUDIO="audio"');
    } else {
      buffer.writeln('#EXT-X-STREAM-INF:BANDWIDTH=4000000');
    }
    buffer.writeln('video.m3u8');

    _writeText(request, buffer.toString(), 'application/vnd.apple.mpegurl');
    await request.response.close();
  }

  Future<void> _writeMedia(
      HttpRequest request, String downloadId, TrackKind kind) async {
    final segments = await _db.segmentsFor(downloadId, kind: kind);
    if (segments.isEmpty) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final longest = segments
        .map((segment) => segment.durationSeconds)
        .fold<double>(0, (a, b) => a > b ? a : b);

    final buffer = StringBuffer()
      ..writeln('#EXTM3U')
      ..writeln('#EXT-X-VERSION:3')
      ..writeln('#EXT-X-PLAYLIST-TYPE:VOD')
      ..writeln('#EXT-X-TARGETDURATION:${longest.ceil().clamp(1, 60)}')
      ..writeln('#EXT-X-MEDIA-SEQUENCE:0');

    final trackName = kind == TrackKind.audio ? 'audio' : 'video';
    for (final segment in segments) {
      buffer
        ..writeln('#EXTINF:${segment.durationSeconds.toStringAsFixed(3)},')
        ..writeln('seg/$trackName/${segment.index}');
    }
    buffer.writeln('#EXT-X-ENDLIST');

    _writeText(request, buffer.toString(), 'application/vnd.apple.mpegurl');
    await request.response.close();
  }

  Future<void> _writeSegment(
    HttpRequest request,
    String downloadId,
    TrackKind kind,
    int index,
  ) async {
    final download = await _db.findDownload(downloadId);
    if (download == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final rows = await _db.segmentsFor(downloadId, kind: kind);
    final row = rows.where((segment) => segment.index == index).firstOrNull;
    if (row == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final nonce = SegmentStore.hexToBytes(download.nonce);
    final totalLength = await _store.segmentSize(downloadId, row.fileName);

    // Range support: mpv rarely asks for one on VOD segments, but a seek can
    // produce one, and answering 200-with-everything would break the seek.
    final range = _parseRange(request.headers.value(HttpHeaders.rangeHeader), totalLength);

    final Uint8List body = await _store.readSegment(
      downloadId: downloadId,
      fileName: row.fileName,
      nonce: nonce,
      segmentIndex: _counterIndex(kind, index),
      start: range?.start ?? 0,
      end: range?.endExclusive,
    );

    final response = request.response;
    response.headers.contentType = ContentType('video', 'mp2t');
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');

    if (range != null) {
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes ${range.start}-${range.endExclusive - 1}/$totalLength',
      );
    }
    response.headers.contentLength = body.length;

    response.add(body);
    await response.close();
  }

  /// Video and audio share one nonce, so their counter indices must not
  /// collide — audio segments are offset into a separate range.
  static int _counterIndex(TrackKind kind, int index) =>
      kind == TrackKind.audio ? index + 1000000 : index;

  void _writeText(HttpRequest request, String body, String mimeType) {
    final bytes = utf8.encode(body);
    request.response.headers.contentType = ContentType.parse(mimeType);
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    request.response.headers.contentLength = bytes.length;
    request.response.add(bytes);
  }

  static _ByteRange? _parseRange(String? header, int totalLength) {
    if (header == null || !header.startsWith('bytes=') || totalLength <= 0) {
      return null;
    }

    final spec = header.substring('bytes='.length).split(',').first.trim();
    final parts = spec.split('-');
    if (parts.length != 2) return null;

    final startText = parts[0].trim();
    final endText = parts[1].trim();

    if (startText.isEmpty) {
      // "bytes=-N": the last N bytes.
      final suffix = int.tryParse(endText);
      if (suffix == null || suffix <= 0) return null;
      final start = (totalLength - suffix).clamp(0, totalLength);
      return _ByteRange(start, totalLength);
    }

    final start = int.tryParse(startText);
    if (start == null || start >= totalLength) return null;
    final end = endText.isEmpty ? totalLength - 1 : int.tryParse(endText);
    if (end == null) return null;

    return _ByteRange(start, (end + 1).clamp(start + 1, totalLength));
  }
}

class _ByteRange {
  const _ByteRange(this.start, this.endExclusive);

  final int start;
  final int endExclusive;
}
