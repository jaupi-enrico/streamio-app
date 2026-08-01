import 'package:flutter_test/flutter_test.dart';
import 'package:streamio/core/download/hls_parser.dart';

/// Manifests shaped like what the backend's extractors actually return.
/// The demuxed case is the important one: Vixcloud serves video and audio as
/// separate media playlists tied together by `#EXT-X-MEDIA`, and a downloader
/// that only follows the video variant produces silent files.
const _demuxedMaster = '''
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Italiano",LANGUAGE="it",DEFAULT=YES,AUTOSELECT=YES,URI="playlist/12345?type=audio&rendition=it&token=abc"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="English",LANGUAGE="en",DEFAULT=NO,AUTOSELECT=YES,URI="playlist/12345?type=audio&rendition=en&token=abc"
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="Italiano",LANGUAGE="it",DEFAULT=NO,URI="playlist/12345?type=subtitle&rendition=it"
#EXT-X-STREAM-INF:BANDWIDTH=1200000,RESOLUTION=854x480,CODECS="avc1.4d401f,mp4a.40.2",AUDIO="audio"
playlist/12345?type=video&rendition=480p&token=abc
#EXT-X-STREAM-INF:BANDWIDTH=4200000,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2",AUDIO="audio"
playlist/12345?type=video&rendition=1080p&token=abc
''';

const _mediaPlaylist = '''
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:6
#EXT-X-MEDIA-SEQUENCE:0
#EXT-X-PLAYLIST-TYPE:VOD
#EXTINF:6.000,
segment0.ts
#EXTINF:6.000,
segment1.ts
#EXTINF:4.520,
/absolute/segment2.ts
#EXT-X-ENDLIST
''';

const _encryptedMediaPlaylist = '''
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:10
#EXT-X-MEDIA-SEQUENCE:5
#EXT-X-KEY:METHOD=AES-128,URI="key.bin",IV=0x0123456789ABCDEF0123456789ABCDEF
#EXTINF:9.009,
seg0.ts
#EXTINF:9.009,
seg1.ts
#EXT-X-KEY:METHOD=NONE
#EXTINF:3.000,
seg2.ts
#EXT-X-ENDLIST
''';

void main() {
  const masterUrl = 'https://vixcloud.co/playlist/12345?token=abc&expires=999';

  group('parseMaster', () {
    final master = parseMaster(_demuxedMaster, masterUrl);

    test('reads every variant with its bandwidth and resolution', () {
      expect(master.variants, hasLength(2));
      expect(master.variants.first.bandwidth, 1200000);
      expect(master.variants.first.resolution, '854x480');
      expect(master.variants.first.label, '480p');
      expect(master.variants.last.label, '1080p');
    });

    test('keeps CODECS intact even though it contains a comma', () {
      // Naive comma splitting is the classic bug here.
      expect(master.variants.first.codecs, 'avc1.4d401f,mp4a.40.2');
    });

    test('resolves relative URIs against the playlist, dropping its query', () {
      // The base is .../playlist/12345?token=abc&expires=999, so the
      // directory is /playlist/ and the parent's signing query is not
      // inherited by the child.
      expect(
        master.variants.first.url,
        'https://vixcloud.co/playlist/playlist/12345?type=video&rendition=480p&token=abc',
      );
      expect(master.variants.first.url, isNot(contains('expires=999')));
    });

    test('separates audio and subtitle renditions', () {
      expect(master.audioRenditions, hasLength(2));
      expect(master.subtitleRenditions, hasLength(1));
    });

    test('best picks the highest bandwidth', () {
      expect(master.best?.bandwidth, 4200000);
    });

    test('audioFor prefers the group default', () {
      final audio = master.audioFor(master.best!);
      expect(audio, isNotNull);
      expect(audio!.language, 'it');
      expect(audio.isDefault, isTrue);
    });

    test('isMasterPlaylist distinguishes the two kinds', () {
      expect(isMasterPlaylist(_demuxedMaster), isTrue);
      expect(isMasterPlaylist(_mediaPlaylist), isFalse);
    });
  });

  group('parseMedia', () {
    test('reads segments, durations and target duration', () {
      final media = parseMedia(_mediaPlaylist, 'https://cdn.example/hls/index.m3u8');

      expect(media.segments, hasLength(3));
      expect(media.targetDuration, 6);
      expect(media.totalDuration, closeTo(16.52, 0.001));
      expect(media.segments.first.url, 'https://cdn.example/hls/segment0.ts');
      expect(media.segments.last.url, 'https://cdn.example/absolute/segment2.ts');
    });

    test('tracks AES-128 keys and stops at METHOD=NONE', () {
      final media =
          parseMedia(_encryptedMediaPlaylist, 'https://cdn.example/hls/index.m3u8');

      expect(media.segments, hasLength(3));
      expect(media.segments[0].key?.isAes128, isTrue);
      expect(media.segments[0].key?.uri, 'https://cdn.example/hls/key.bin');
      expect(media.segments[1].key, isNotNull);
      // METHOD=NONE ends encryption for everything after it.
      expect(media.segments[2].key, isNull);
    });

    test('uses the explicit IV when the playlist gives one', () {
      final media =
          parseMedia(_encryptedMediaPlaylist, 'https://cdn.example/hls/index.m3u8');
      final iv = ivForSegment(media.segments.first);

      expect(iv, hasLength(16));
      expect(iv.first, 0x01);
      expect(iv[1], 0x23);
    });

    test('derives the IV from the media sequence number otherwise', () {
      final media = parseMedia(_mediaPlaylist, 'https://cdn.example/hls/index.m3u8');
      // MEDIA-SEQUENCE is 0 here, so segment 2's IV is 2 big-endian in 16 bytes.
      final iv = ivForSegment(media.segments[2]);

      expect(iv, hasLength(16));
      expect(iv.last, 2);
      expect(iv.take(15), everyElement(0));
    });
  });

  group('resolveUri', () {
    const base = 'https://cdn.example/a/b/index.m3u8?token=1';

    test('leaves absolute URLs alone', () {
      expect(resolveUri('https://other/x.ts', base), 'https://other/x.ts');
    });

    test('resolves a root-relative path against the origin', () {
      expect(resolveUri('/x.ts', base), 'https://cdn.example/x.ts');
    });

    test('resolves a relative path against the directory', () {
      expect(resolveUri('x.ts', base), 'https://cdn.example/a/b/x.ts');
    });
  });
}
