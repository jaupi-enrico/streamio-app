import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

part 'app_database.g.dart';

/// Lifecycle of a download. `queued`/`downloading`/`paused` are resumable —
/// the segment rows record exactly how far it got, so a killed app picks up
/// where it left off instead of starting over.
enum DownloadStatus { queued, downloading, paused, completed, failed }

/// Which stream a segment belongs to. Vixcloud output is demuxed, so a single
/// download normally has both a `video` and an `audio` track, each with its
/// own segment list and its own generated playlist at playback time.
enum TrackKind { video, audio, subtitle }

/// One downloaded title (a movie, or one episode).
@DataClassName('DownloadRow')
class Downloads extends Table {
  TextColumn get id => text()();

  TextColumn get provider => text()();
  TextColumn get showId => text()();
  TextColumn get contentId => text()();
  TextColumn get contentType => text().withDefault(const Constant('episode'))();

  TextColumn get title => text()();
  TextColumn get episodeLabel => text().nullable()();
  TextColumn get poster => text().nullable()();
  TextColumn get quality => text().nullable()();

  IntColumn get durationSeconds => integer().withDefault(const Constant(0))();
  IntColumn get status => intEnum<DownloadStatus>()();
  IntColumn get bytesDownloaded => integer().withDefault(const Constant(0))();
  IntColumn get segmentsTotal => integer().withDefault(const Constant(0))();
  IntColumn get segmentsDone => integer().withDefault(const Constant(0))();

  /// Hex-encoded per-download CTR nonce (see SegmentStore).
  TextColumn get nonce => text()();

  TextColumn get errorMessage => text().nullable()();

  /// Locally accumulated playback position, flushed to
  /// `POST /api/account/history` once the server is reachable again.
  IntColumn get progressSeconds => integer().withDefault(const Constant(0))();
  BoolColumn get progressSynced => boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One media segment of one track.
@DataClassName('DownloadSegmentRow')
class DownloadSegments extends Table {
  TextColumn get downloadId => text().references(Downloads, #id, onDelete: KeyAction.cascade)();
  IntColumn get kind => intEnum<TrackKind>()();
  IntColumn get index => integer()();

  TextColumn get sourceUrl => text()();
  TextColumn get fileName => text()();
  RealColumn get durationSeconds => real().withDefault(const Constant(0))();
  IntColumn get byteLength => integer().withDefault(const Constant(0))();
  BoolColumn get done => boolean().withDefault(const Constant(false))();

  /// Upstream `#EXT-X-KEY` for this segment, when the source playlist is
  /// AES-128 encrypted. Kept per segment because a playlist can rotate keys
  /// mid-stream. Both are cleared once the segment is stored — by then it has
  /// been decrypted and re-encrypted under our own key.
  TextColumn get keyUri => text().nullable()();

  /// Hex-encoded 16-byte IV (explicit `IV=`, or derived from the media
  /// sequence number per RFC 8216 §5.2).
  TextColumn get keyIv => text().nullable()();

  @override
  Set<Column> get primaryKey => {downloadId, kind, index};
}

@DriftDatabase(tables: [Downloads, DownloadSegments])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());

  /// Test seam: an in-memory database with the same schema.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  // ── Downloads ─────────────────────────────────────────────

  Stream<List<DownloadRow>> watchAll() =>
      (select(downloads)..orderBy([(d) => OrderingTerm.desc(d.createdAt)])).watch();

  Future<List<DownloadRow>> allDownloads() =>
      (select(downloads)..orderBy([(d) => OrderingTerm.desc(d.createdAt)])).get();

  Future<DownloadRow?> findDownload(String id) =>
      (select(downloads)..where((d) => d.id.equals(id))).getSingleOrNull();

  /// The download for a given piece of content, if one exists — used by the
  /// details/watch screens to show "Downloaded" instead of "Download".
  Future<DownloadRow?> findByContent(String provider, String contentId) =>
      (select(downloads)
            ..where((d) => d.provider.equals(provider) & d.contentId.equals(contentId)))
          .getSingleOrNull();

  Stream<DownloadRow?> watchByContent(String provider, String contentId) =>
      (select(downloads)
            ..where((d) => d.provider.equals(provider) & d.contentId.equals(contentId)))
          .watchSingleOrNull();

  /// Downloads left mid-flight by a kill/crash. They're resumable, but must
  /// not look "active" at launch when nothing is actually running.
  Future<List<DownloadRow>> interruptedDownloads() => (select(downloads)
        ..where((d) => d.status.equalsValue(DownloadStatus.downloading)))
      .get();

  Future<void> upsertDownload(DownloadsCompanion row) =>
      into(downloads).insertOnConflictUpdate(row);

  Future<void> updateDownload(String id, DownloadsCompanion changes) =>
      (update(downloads)..where((d) => d.id.equals(id))).write(changes);

  Future<void> deleteDownload(String id) async {
    await (delete(downloadSegments)..where((s) => s.downloadId.equals(id))).go();
    await (delete(downloads)..where((d) => d.id.equals(id))).go();
  }

  // ── Segments ──────────────────────────────────────────────

  Future<void> insertSegments(List<DownloadSegmentsCompanion> rows) async {
    await batch((batch) => batch.insertAll(downloadSegments, rows,
        mode: InsertMode.insertOrReplace));
  }

  Future<List<DownloadSegmentRow>> segmentsFor(String downloadId, {TrackKind? kind}) {
    final query = select(downloadSegments)
      ..where((s) =>
          kind == null
              ? s.downloadId.equals(downloadId)
              : s.downloadId.equals(downloadId) & s.kind.equalsValue(kind))
      ..orderBy([(s) => OrderingTerm.asc(s.index)]);
    return query.get();
  }

  Future<List<DownloadSegmentRow>> pendingSegments(String downloadId) =>
      (select(downloadSegments)
            ..where((s) => s.downloadId.equals(downloadId) & s.done.equals(false))
            ..orderBy([(s) => OrderingTerm.asc(s.index)]))
          .get();

  Future<void> markSegmentDone(
    String downloadId,
    TrackKind kind,
    int index,
    int byteLength,
  ) =>
      (update(downloadSegments)
            ..where((s) =>
                s.downloadId.equals(downloadId) &
                s.kind.equalsValue(kind) &
                s.index.equals(index)))
          .write(DownloadSegmentsCompanion(
        done: const Value(true),
        byteLength: Value(byteLength),
      ));

  /// Which track kinds this download actually has segments for — the
  /// generated master playlist only advertises an audio rendition when one
  /// was really downloaded.
  Future<Set<TrackKind>> trackKinds(String downloadId) async {
    final rows = await (selectOnly(downloadSegments, distinct: true)
          ..addColumns([downloadSegments.kind])
          ..where(downloadSegments.downloadId.equals(downloadId)))
        .get();
    return rows
        .map((row) => row.read(downloadSegments.kind))
        .whereType<TrackKind>()
        .toSet();
  }
}

LazyDatabase _open() {
  return LazyDatabase(() async {
    final directory = await getApplicationSupportDirectory();
    final file = File(p.join(directory.path, 'streamio.sqlite'));

    // Works around old Android sqlite builds; harmless elsewhere.
    if (Platform.isAndroid) await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();

    return NativeDatabase.createInBackground(file);
  });
}
