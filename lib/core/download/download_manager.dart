import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
// `Value` (drift's "set this column" wrapper) — the DB rows are written from
// here, so the companion objects come with it.
import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../api/content_api.dart';
import '../db/app_database.dart';
import '../models/models.dart';
import 'hls_parser.dart';
import 'segment_store.dart';

/// A quality the user can pick in the download sheet, resolved from the
/// stream's master playlist.
class DownloadOption {
  const DownloadOption({
    required this.variant,
    required this.audio,
    required this.estimatedBytes,
  });

  final HlsVariant variant;
  final HlsRendition? audio;

  /// bitrate × duration. Rough, but enough to warn about a 4 GB download
  /// before it starts.
  final int estimatedBytes;

  String get label => variant.label;
}

/// What the download sheet needs before it can start anything: the resolved
/// stream plus the qualities it offers.
class DownloadPlan {
  const DownloadPlan({
    required this.source,
    required this.master,
    required this.options,
    required this.headers,
  });

  final PlaybackSource source;
  final HlsMaster? master;
  final List<DownloadOption> options;
  final Map<String, String> headers;
}

/// Downloads a title into the app-private encrypted store.
///
/// The shape of the work mirrors the web downloader in
/// `web/public/scripts/watch.js` — resolve a stream, parse the master
/// playlist, take the video variant plus its demuxed audio rendition, then
/// pull every segment with a bounded worker pool and retries. Where the web
/// version muxes to MP4 with ffmpeg and hands the user a file, this one
/// encrypts each segment into the app sandbox and keeps a row per segment, so
/// a killed download resumes instead of restarting.
class DownloadManager {
  DownloadManager({
    required AppDatabase database,
    required SegmentStore store,
    required ApiClient client,
    required ContentApi content,
    Dio? httpClient,
  })  : _db = database,
        _store = store,
        _client = client,
        _content = content,
        _http = httpClient ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 60),
              responseType: ResponseType.bytes,
              validateStatus: (status) => status != null && status < 500,
            ));

  static const _concurrency = 5;
  static const _maxRetries = 3;

  final AppDatabase _db;
  final SegmentStore _store;
  final ApiClient _client;
  final ContentApi _content;
  final Dio _http;

  final _active = <String, _ActiveDownload>{};
  final _events = StreamController<String>.broadcast();

  /// Emits a download id whenever its progress changes, for UI that wants to
  /// react faster than the database stream's granularity.
  Stream<String> get events => _events.stream;

  bool isActive(String downloadId) => _active.containsKey(downloadId);

  void dispose() {
    for (final active in _active.values) {
      active.cancelled = true;
    }
    _active.clear();
    _events.close();
    _http.close(force: true);
  }

  /// Anything left `downloading` when the app was killed isn't running now.
  /// Mark it paused so the UI offers "resume" rather than a stuck spinner.
  Future<void> reconcileOnStartup() async {
    for (final row in await _db.interruptedDownloads()) {
      await _db.updateDownload(
          row.id, const DownloadsCompanion(status: Value(DownloadStatus.paused)));
    }
  }

  // ── Planning ──────────────────────────────────────────────

  /// Resolves the stream and reads its master playlist so the user can choose
  /// a quality. Nothing is written to disk yet.
  Future<DownloadPlan> plan({
    required String provider,
    required String contentId,
    required String contentType,
  }) async {
    final servers = await _content.servers(contentId,
        provider: provider, contentType: contentType);
    if (servers.isEmpty) {
      throw const ApiException('No servers are available for this title.');
    }

    final source = await _content.resolveVideo(contentId, servers.first,
        provider: provider, contentType: contentType);

    final headers = _headersFor(source);
    final manifestUrl = source.url;

    // Some providers hand back the manifest inline rather than a URL; there's
    // then nothing to fetch for the top level.
    final text = source.inlineManifest ??
        (manifestUrl.isEmpty
            ? null
            : await _fetchText(manifestUrl, headers: headers));

    if (text == null || !isMasterPlaylist(text)) {
      // A media playlist with no variants: one implicit "default" quality.
      return DownloadPlan(
        source: source,
        master: null,
        options: const [
          DownloadOption(
            variant: HlsVariant(url: '', bandwidth: 0),
            audio: null,
            estimatedBytes: 0,
          ),
        ],
        headers: headers,
      );
    }

    final master = parseMaster(text, manifestUrl);
    final options = <DownloadOption>[];
    final sorted = [...master.variants]
      ..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));

    for (final variant in sorted) {
      options.add(DownloadOption(
        variant: variant,
        audio: master.audioFor(variant),
        estimatedBytes: 0,
      ));
    }

    return DownloadPlan(
      source: source,
      master: master,
      options: options,
      headers: headers,
    );
  }

  // ── Enqueue ───────────────────────────────────────────────

  /// Creates the download row and its segment rows, then starts fetching.
  /// Returns the new download's id.
  Future<String> enqueue({
    required String provider,
    required String showId,
    required String contentId,
    required String contentType,
    required String title,
    String? episodeLabel,
    String? poster,
    required DownloadPlan plan,
    required DownloadOption option,
  }) async {
    final existing = await _db.findByContent(provider, contentId);
    if (existing != null && existing.status == DownloadStatus.completed) {
      return existing.id;
    }
    if (existing != null) await _remove(existing.id);

    final id = const Uuid().v4();
    final nonce = SegmentStore.newNonce();

    await _db.upsertDownload(DownloadsCompanion.insert(
      id: id,
      provider: provider,
      showId: showId,
      contentId: contentId,
      title: title,
      status: DownloadStatus.queued,
      nonce: SegmentStore.bytesToHex(nonce),
      contentType: Value(contentType),
      episodeLabel: Value(episodeLabel),
      poster: Value(poster),
      quality: Value(option.label),
    ));

    // The playlists are read here rather than at plan time so the download
    // row exists first — if the app dies mid-enumeration there's a row to
    // clean up instead of orphaned files.
    try {
      final tracks = await _enumerateSegments(plan, option);
      if (tracks.isEmpty) {
        throw const ApiException('This stream has no downloadable segments.');
      }

      final rows = <DownloadSegmentsCompanion>[];
      var duration = 0.0;
      for (final track in tracks) {
        if (track.kind == TrackKind.video) duration = track.media.totalDuration;
        for (var i = 0; i < track.media.segments.length; i++) {
          final segment = track.media.segments[i];
          final key = segment.key;
          rows.add(DownloadSegmentsCompanion.insert(
            downloadId: id,
            kind: track.kind,
            index: i,
            sourceUrl: segment.url,
            fileName: '${track.kind.name}_$i.bin',
            durationSeconds: Value(segment.durationSeconds),
            keyUri: Value(key != null && key.isAes128 ? key.uri : null),
            keyIv: Value(key != null && key.isAes128
                ? SegmentStore.bytesToHex(ivForSegment(segment))
                : null),
          ));
        }
      }

      await _db.insertSegments(rows);
      await _db.updateDownload(
        id,
        DownloadsCompanion(
          segmentsTotal: Value(rows.length),
          durationSeconds: Value(duration.round()),
        ),
      );
    } catch (err) {
      await _db.updateDownload(
        id,
        DownloadsCompanion(
          status: const Value(DownloadStatus.failed),
          errorMessage: Value(_message(err)),
        ),
      );
      _events.add(id);
      rethrow;
    }

    unawaited(_run(id, plan.headers));
    return id;
  }

  Future<void> resume(String downloadId) async {
    if (_active.containsKey(downloadId)) return;

    final row = await _db.findDownload(downloadId);
    if (row == null || row.status == DownloadStatus.completed) return;

    // Segment URLs are signed and expire in minutes, so a resume can't reuse
    // the stored ones — re-resolve the stream and re-point the pending rows
    // at fresh URLs before continuing.
    try {
      await _refreshSegmentUrls(row);
    } catch (err) {
      await _db.updateDownload(
        downloadId,
        DownloadsCompanion(
          status: const Value(DownloadStatus.failed),
          errorMessage: Value(_message(err)),
        ),
      );
      _events.add(downloadId);
      return;
    }

    unawaited(_run(downloadId, const {}));
  }

  void pause(String downloadId) {
    final active = _active[downloadId];
    if (active == null) return;
    active.cancelled = true;
  }

  Future<void> remove(String downloadId) async {
    pause(downloadId);
    await _remove(downloadId);
  }

  Future<void> _remove(String downloadId) async {
    await _db.deleteDownload(downloadId);
    await _store.deleteDownload(downloadId);
    _events.add(downloadId);
  }

  // ── Segment enumeration ───────────────────────────────────

  Future<List<_Track>> _enumerateSegments(
      DownloadPlan plan, DownloadOption option) async {
    final tracks = <_Track>[];

    final videoUrl = option.variant.url.isNotEmpty ? option.variant.url : plan.source.url;
    if (videoUrl.isEmpty && plan.source.inlineManifest == null) return tracks;

    final videoText = videoUrl.isEmpty
        ? plan.source.inlineManifest!
        : await _fetchText(videoUrl, headers: plan.headers);
    tracks.add(_Track(
      kind: TrackKind.video,
      media: parseMedia(videoText, videoUrl),
    ));

    final audio = option.audio;
    if (audio != null) {
      final audioText = await _fetchText(audio.url, headers: plan.headers);
      tracks.add(_Track(
        kind: TrackKind.audio,
        media: parseMedia(audioText, audio.url),
      ));
    }

    return tracks;
  }

  /// Re-resolves the stream and rewrites every not-yet-downloaded segment's
  /// URL, matching by index. Signed CDN URLs don't survive a pause.
  Future<void> _refreshSegmentUrls(DownloadRow row) async {
    final plan = await this.plan(
      provider: row.provider,
      contentId: row.contentId,
      contentType: row.contentType,
    );

    // Prefer the same quality label the download started at; fall back to the
    // best available if that rendition is gone.
    final option = plan.options.firstWhere(
      (candidate) => candidate.label == row.quality,
      orElse: () => plan.options.first,
    );

    final tracks = await _enumerateSegments(plan, option);
    final updates = <DownloadSegmentsCompanion>[];

    for (final track in tracks) {
      final existing = await _db.segmentsFor(row.id, kind: track.kind);
      for (final segment in existing) {
        if (segment.done) continue;
        if (segment.index >= track.media.segments.length) continue;
        updates.add(DownloadSegmentsCompanion.insert(
          downloadId: row.id,
          kind: track.kind,
          index: segment.index,
          sourceUrl: track.media.segments[segment.index].url,
          fileName: segment.fileName,
          durationSeconds: Value(segment.durationSeconds),
          done: const Value(false),
        ));
      }
    }

    if (updates.isNotEmpty) await _db.insertSegments(updates);
    _refreshedHeaders[row.id] = plan.headers;
  }

  /// Headers from the most recent re-resolve, so a resumed download keeps
  /// sending the Referer/UA the CDN expects.
  final _refreshedHeaders = <String, Map<String, String>>{};

  // ── The download loop ─────────────────────────────────────

  Future<void> _run(String downloadId, Map<String, String> headers) async {
    if (_active.containsKey(downloadId)) return;

    final active = _ActiveDownload();
    _active[downloadId] = active;

    final effectiveHeaders =
        headers.isNotEmpty ? headers : (_refreshedHeaders[downloadId] ?? const {});

    // Cached for this run only: an AES-128 key URL is short-lived, and every
    // segment of a playlist normally shares one.
    final keys = <String, Uint8List>{};

    try {
      final row = await _db.findDownload(downloadId);
      if (row == null) return;

      await _db.updateDownload(downloadId,
          const DownloadsCompanion(status: Value(DownloadStatus.downloading)));
      _events.add(downloadId);

      final nonce = SegmentStore.hexToBytes(row.nonce);
      final pending = await _db.pendingSegments(downloadId);
      var bytes = row.bytesDownloaded;
      var done = row.segmentsDone;

      await _pool(pending, (segment) async {
        if (active.cancelled) return;

        final data = await _fetchSegment(
          segment,
          headers: effectiveHeaders,
          keys: keys,
          downloadId: downloadId,
        );
        if (active.cancelled || data == null) return;

        final written = await _store.writeSegment(
          downloadId: downloadId,
          fileName: segment.fileName,
          nonce: nonce,
          segmentIndex: segment.kind == TrackKind.audio
              ? segment.index + 1000000
              : segment.index,
          plaintext: data,
        );

        await _db.markSegmentDone(downloadId, segment.kind, segment.index, written);

        bytes += written;
        done += 1;
        await _db.updateDownload(
          downloadId,
          DownloadsCompanion(
            bytesDownloaded: Value(bytes),
            segmentsDone: Value(done),
          ),
        );
        _events.add(downloadId);
      });

      if (active.cancelled) {
        await _db.updateDownload(downloadId,
            const DownloadsCompanion(status: Value(DownloadStatus.paused)));
      } else {
        final remaining = await _db.pendingSegments(downloadId);
        if (remaining.isEmpty) {
          await _db.updateDownload(
            downloadId,
            DownloadsCompanion(
              status: const Value(DownloadStatus.completed),
              completedAt: Value(DateTime.now()),
              errorMessage: const Value(null),
            ),
          );
        } else {
          await _db.updateDownload(
            downloadId,
            const DownloadsCompanion(
              status: Value(DownloadStatus.failed),
              errorMessage: Value('Some parts could not be downloaded.'),
            ),
          );
        }
      }
    } catch (err) {
      await _db.updateDownload(
        downloadId,
        DownloadsCompanion(
          status: const Value(DownloadStatus.failed),
          errorMessage: Value(_message(err)),
        ),
      );
    } finally {
      _active.remove(downloadId);
      _events.add(downloadId);
    }
  }

  /// Bounded-concurrency worker pool — `pool()` in `watch.js`.
  Future<void> _pool<T>(List<T> items, Future<void> Function(T item) work) async {
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= items.length) return;
        await work(items[index]);
      }
    }

    await Future.wait(
      List.generate(_concurrency.clamp(1, items.isEmpty ? 1 : items.length), (_) => worker()),
    );
  }

  Future<Uint8List?> _fetchSegment(
    DownloadSegmentRow segment, {
    required Map<String, String> headers,
    required Map<String, Uint8List> keys,
    required String downloadId,
  }) async {
    final bytes = await _fetchBytes(segment.sourceUrl, headers: headers);
    if (bytes == null) return null;

    final keyUri = segment.keyUri;
    final keyIv = segment.keyIv;
    if (keyUri == null || keyIv == null) return bytes;

    // Undo the upstream AES-128 here, so what lands on disk is plain media
    // under our own key. Keeping the upstream encryption instead would mean a
    // download stops playing the moment that key URL expires. The key is
    // per-playlist in practice, so it's fetched once and cached for the run.
    final key = keys[keyUri] ??= await _fetchKey(keyUri, headers: headers);
    return decryptAes128Cbc(
      data: bytes,
      key: key,
      iv: SegmentStore.hexToBytes(keyIv),
    );
  }

  Future<Uint8List> _fetchKey(String url, {Map<String, String> headers = const {}}) async {
    final bytes = await _fetchBytes(url, headers: headers);
    if (bytes == null || bytes.length != 16) {
      throw const ApiException('Could not fetch the stream decryption key.');
    }
    return bytes;
  }

  /// Fetches with retries, falling back to the server's proxy on a 403.
  ///
  /// Vixcloud's CDN 403s requests whose Referer/Origin don't match what its
  /// edge expects, and which edge you hit depends on the network — the same
  /// problem `needsSourceProxy()` works around in the browser. Going through
  /// `/api/cast-proxy` makes the server do the fetch with a fixed
  /// Referer/User-Agent instead.
  Future<Uint8List?> _fetchBytes(String url, {Map<String, String> headers = const {}}) async {
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        final response = await _http.get<List<int>>(
          url,
          options: Options(headers: headers, responseType: ResponseType.bytes),
        );
        final status = response.statusCode ?? 0;

        if (status == 200 || status == 206) {
          final data = response.data;
          if (data != null) return Uint8List.fromList(data);
        }

        if (status == 403 || status == 401) {
          final proxied = await _fetchViaProxy(url);
          if (proxied != null) return proxied;
        }
      } catch (_) {
        // Retried below; a transient network failure mid-download shouldn't
        // fail the whole title.
      }

      if (attempt < _maxRetries - 1) {
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
    return null;
  }

  Future<Uint8List?> _fetchViaProxy(String url) async {
    try {
      final proxyUrl =
          '${_client.baseUrl}/api/cast-proxy?url=${Uri.encodeComponent(url)}';
      final response = await _http.get<List<int>>(
        proxyUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if ((response.statusCode == 200 || response.statusCode == 206) && data != null) {
        return Uint8List.fromList(data);
      }
    } catch (_) {
      // Fall through: the caller retries or gives up on this segment.
    }
    return null;
  }

  Future<String> _fetchText(String url, {Map<String, String> headers = const {}}) async {
    final bytes = await _fetchBytes(url, headers: headers);
    if (bytes == null) {
      throw const ApiException('Could not read the stream playlist.');
    }
    return String.fromCharCodes(bytes);
  }

  /// Referer/User-Agent the extractor computed for this stream. The CDNs
  /// reject requests without them, so every fetch carries them.
  Map<String, String> _headersFor(PlaybackSource source) => {
        if (source.headers.isNotEmpty) ...source.headers,
      };

  static String _message(Object error) =>
      error is ApiException ? error.message : 'The download failed.';
}

class _Track {
  const _Track({required this.kind, required this.media});

  final TrackKind kind;
  final HlsMedia media;
}

class _ActiveDownload {
  bool cancelled = false;
}
