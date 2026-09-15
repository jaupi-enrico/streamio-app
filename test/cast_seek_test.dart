import 'package:flutter_test/flutter_test.dart';
import 'package:streamio/core/cast/cast_service.dart';

/// The ±10s buttons on the cast panel.
///
/// These are arithmetic, and the arithmetic is the bug: the panel used to send
/// `GoogleCastMediaSeekOption(position: ±10s, relative: true)` and let the
/// receiver resolve it, which is correct on iOS and silently wrong on Android
/// — the plugin's `GoogleCastSeekOptionsBuilder.fromMap` never reads
/// `relative`, so the receiver was handed an *absolute* `setPosition(10s)` and
/// "forward 10" jumped to 0:10 from anywhere in the film. The target is
/// therefore resolved here, on both platforms.
void main() {
  group('resolveSeekTarget', () {
    test('skips forward from the current position, not from zero', () {
      expect(
        CastService.resolveSeekTarget(
          from: const Duration(minutes: 42),
          offset: const Duration(seconds: 10),
          duration: const Duration(hours: 2),
        ),
        const Duration(minutes: 42, seconds: 10),
      );
    });

    test('skips back from the current position', () {
      expect(
        CastService.resolveSeekTarget(
          from: const Duration(minutes: 42),
          offset: const Duration(seconds: -10),
          duration: const Duration(hours: 2),
        ),
        const Duration(minutes: 41, seconds: 50),
      );
    });

    test('never lands before the start', () {
      expect(
        CastService.resolveSeekTarget(
          from: const Duration(seconds: 4),
          offset: const Duration(seconds: -10),
          duration: const Duration(hours: 2),
        ),
        Duration.zero,
      );
    });

    test('stops short of the end, which would end playback', () {
      final target = CastService.resolveSeekTarget(
        from: const Duration(hours: 1, minutes: 59, seconds: 58),
        offset: const Duration(seconds: 10),
        duration: const Duration(hours: 2),
      );
      expect(target, lessThan(const Duration(hours: 2)));
      expect(target, greaterThan(const Duration(hours: 1, minutes: 59)));
    });

    test('an unknown duration is not a ceiling of zero', () {
      // Duration arrives from STATE or the media status and is legitimately 0
      // until one of them lands; clamping to it would pin every skip to the
      // start of the stream.
      expect(
        CastService.resolveSeekTarget(
          from: const Duration(minutes: 10),
          offset: const Duration(seconds: 10),
          duration: Duration.zero,
        ),
        const Duration(minutes: 10, seconds: 10),
      );
      expect(
        CastService.resolveSeekTarget(
          from: const Duration(minutes: 10),
          offset: const Duration(seconds: 10),
        ),
        const Duration(minutes: 10, seconds: 10),
      );
    });
  });
}
