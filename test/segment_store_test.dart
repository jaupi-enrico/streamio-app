import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:streamio/core/download/segment_store.dart';

/// The crypto behind offline downloads. What matters is that CTR is truly
/// seekable — the loopback player server decrypts arbitrary byte ranges out
/// of a segment file, and if a mid-block offset were mishandled the result
/// would be silent corruption rather than an error.
void main() {
  final key = Uint8List.fromList(List<int>.generate(32, (i) => i * 7 % 256));
  final nonce = Uint8List.fromList(List<int>.generate(16, (i) => 255 - i));

  Uint8List sample(int length) {
    final random = Random(1234);
    return Uint8List.fromList(
        List<int>.generate(length, (_) => random.nextInt(256)));
  }

  group('ctrTransform', () {
    test('round-trips a whole segment', () {
      final plaintext = sample(5000);

      final encrypted = ctrTransform(
          data: plaintext, key: key, nonce: nonce, segmentIndex: 3);
      final decrypted = ctrTransform(
          data: encrypted, key: key, nonce: nonce, segmentIndex: 3);

      expect(encrypted, isNot(equals(plaintext)));
      expect(decrypted, equals(plaintext));
    });

    test('output is the same length as the input', () {
      // Not a block cipher's usual behavior — CTR is a stream cipher, which
      // is what makes a byte offset map to a keystream offset.
      for (final length in [1, 15, 16, 17, 4096, 5001]) {
        final encrypted = ctrTransform(
            data: sample(length), key: key, nonce: nonce, segmentIndex: 0);
        expect(encrypted.length, length);
      }
    });

    test('decrypts a range starting on a block boundary', () {
      final plaintext = sample(4096);
      final encrypted = ctrTransform(
          data: plaintext, key: key, nonce: nonce, segmentIndex: 9);

      const start = 1024;
      const end = 2048;
      final slice = Uint8List.sublistView(encrypted, start, end);

      final decrypted = ctrTransform(
        data: slice,
        key: key,
        nonce: nonce,
        segmentIndex: 9,
        byteOffset: start,
      );

      expect(decrypted, equals(Uint8List.sublistView(plaintext, start, end)));
    });

    test('decrypts a range starting mid-block', () {
      final plaintext = sample(4096);
      final encrypted = ctrTransform(
          data: plaintext, key: key, nonce: nonce, segmentIndex: 2);

      // 1000 is deliberately not a multiple of 16.
      const start = 1000;
      const end = 3333;
      final slice = Uint8List.sublistView(encrypted, start, end);

      final decrypted = ctrTransform(
        data: slice,
        key: key,
        nonce: nonce,
        segmentIndex: 2,
        byteOffset: start,
      );

      expect(decrypted, equals(Uint8List.sublistView(plaintext, start, end)));
    });

    test('different segments of one download get different keystreams', () {
      final plaintext = sample(64);

      final first = ctrTransform(
          data: plaintext, key: key, nonce: nonce, segmentIndex: 0);
      final second = ctrTransform(
          data: plaintext, key: key, nonce: nonce, segmentIndex: 1);

      // Identical plaintext under a repeated keystream would produce
      // identical ciphertext, which is the failure mode this guards against.
      expect(first, isNot(equals(second)));
    });

    test('the wrong key does not recover the plaintext', () {
      final plaintext = sample(256);
      final encrypted = ctrTransform(
          data: plaintext, key: key, nonce: nonce, segmentIndex: 0);

      final otherKey = Uint8List.fromList(List<int>.filled(32, 1));
      final decrypted = ctrTransform(
          data: encrypted, key: otherKey, nonce: nonce, segmentIndex: 0);

      expect(decrypted, isNot(equals(plaintext)));
    });
  });

  group('hex helpers', () {
    test('round-trip', () {
      final bytes = sample(32);
      final hex = SegmentStore.bytesToHex(bytes);
      expect(hex.length, 64);
      expect(SegmentStore.hexToBytes(hex), equals(bytes));
    });
  });

  group('newNonce', () {
    test('is 16 bytes and not repeated', () {
      final first = SegmentStore.newNonce();
      final second = SegmentStore.newNonce();
      expect(first.length, 16);
      expect(first, isNot(equals(second)));
    });
  });
}
