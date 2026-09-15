import 'package:flutter_test/flutter_test.dart';
import 'package:streamio/core/cast/cast_service.dart';

/// The content type a LOAD carries is not cosmetic: CAF looks it up in its own
/// table to choose a playback pipeline, and the lookup is case-sensitive. An
/// `application/x-mpegURL` went to the plain media element instead of the HLS
/// player, failed ~13s into the load as error 100 (MEDIA_UNKNOWN), and left the
/// receiver page unable to play anything afterwards — while the same stream
/// cast fine from the browser sender, which always sent it lowercase.
void main() {
  group('cast content type', () {
    test('HLS is the canonical lowercase spelling', () {
      expect(kCastHlsContentType, 'application/x-mpegurl');
      expect(castContentTypeFor(progressive: false), kCastHlsContentType);
    });

    test('progressive is lowercase too', () {
      expect(kCastProgressiveContentType, 'video/mp4');
      expect(castContentTypeFor(progressive: true), kCastProgressiveContentType);
    });

    test('no sender may ship a spelling with an uppercase letter in it', () {
      for (final type in [kCastHlsContentType, kCastProgressiveContentType]) {
        expect(type, type.toLowerCase(), reason: type);
      }
    });
  });
}
