import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streamio/core/db/app_database.dart';

/// `trackKinds` decides whether the offline master declares a demuxed audio
/// rendition. When it came back empty, every download with separate audio
/// (StreamingCommunity's Vixcloud streams, for one) played video only.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('reports both tracks of a demuxed download', () async {
    await db.upsertDownload(DownloadsCompanion.insert(
      id: 'd1',
      provider: 'streamingcommunity',
      showId: 's',
      contentId: 'c',
      title: 't',
      status: DownloadStatus.completed,
      nonce: '00',
    ));
    await db.insertSegments([
      for (final kind in [TrackKind.video, TrackKind.audio])
        DownloadSegmentsCompanion.insert(
          downloadId: 'd1',
          kind: kind,
          index: 0,
          sourceUrl: 'https://cdn/${kind.name}/0',
          fileName: '${kind.name}_0.bin',
          durationSeconds: const Value(4),
        ),
    ]);

    expect(await db.trackKinds('d1'), {TrackKind.video, TrackKind.audio});
  });
}
