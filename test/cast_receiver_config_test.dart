import 'package:flutter_test/flutter_test.dart';
import 'package:streamio/core/config/cast_receiver_config.dart';

/// A wrong receiver id fails silently — the Cast SDK just discovers no devices
/// that support it — so the only feedback possible is rejecting the wrong
/// shape before it is ever stored.
void main() {
  group('CastReceiverConfig.normalize', () {
    test('accepts a well-formed id', () {
      expect(CastReceiverConfig.normalize('BF64D6B2'), 'BF64D6B2');
    });

    test('uppercases lowercase hex, as the console prints ids uppercase', () {
      expect(CastReceiverConfig.normalize('bf64d6b2'), 'BF64D6B2');
    });

    test('tolerates the whitespace that comes with a paste', () {
      expect(CastReceiverConfig.normalize('  BF64D6B2 \n'), 'BF64D6B2');
    });

    test('rejects the wrong length', () {
      expect(CastReceiverConfig.normalize('BF64D6B'), isNull);
      expect(CastReceiverConfig.normalize('BF64D6B22'), isNull);
      expect(CastReceiverConfig.normalize(''), isNull);
    });

    test('rejects non-hex characters', () {
      // 'G' and 'Z' are not hex; a receiver id copied out of some other field
      // (a project name, a URL fragment) lands here.
      expect(CastReceiverConfig.normalize('BF64D6BG'), isNull);
      expect(CastReceiverConfig.normalize('ZZZZZZZZ'), isNull);
      expect(CastReceiverConfig.normalize('BF64-D6B'), isNull);
    });

    test('isValid agrees with normalize', () {
      expect(CastReceiverConfig.isValid('cc1ad845'), isTrue);
      expect(CastReceiverConfig.isValid('nope'), isFalse);
    });
  });
}
