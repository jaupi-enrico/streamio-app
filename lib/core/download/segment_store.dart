import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/stream/ctr.dart';
import 'package:pointycastle/api.dart';

/// On-disk home for downloaded media, and the encryption around it.
///
/// Two things make a download app-only:
///
///  1. **Location** — everything lives under `getApplicationSupportDirectory()`,
///     the app's private sandbox. Not the gallery, not Downloads, not external
///     storage: no other app and no file manager can see it, and uninstalling
///     the app takes it with it.
///  2. **Encryption** — each segment is AES-CTR encrypted with a 256-bit key
///     generated on first use and kept in the platform keystore/keychain
///     (`flutter_secure_storage`). A segment file copied off the device with
///     ADB or root is just noise without that key.
///
/// CTR rather than CBC or GCM specifically because it's *seekable*: the
/// keystream at byte N depends only on N, so the loopback server can answer a
/// ranged request by jumping to the right counter block instead of decrypting
/// the file from the beginning. (GCM would authenticate, but can't be
/// random-accessed, and integrity isn't the threat model here — the file
/// never leaves the device.)
class SegmentStore {
  SegmentStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _masterKeyName = 'streamio.download_master_key';
  static const _blockSize = 16;

  final FlutterSecureStorage _storage;
  Uint8List? _masterKey;
  Directory? _root;

  /// `<app support>/downloads/`. Created on first use.
  Future<Directory> root() async {
    final cached = _root;
    if (cached != null) return cached;

    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'downloads'));
    if (!await directory.exists()) await directory.create(recursive: true);
    _root = directory;
    return directory;
  }

  Future<Directory> directoryFor(String downloadId) async {
    final base = await root();
    final directory = Directory(p.join(base.path, downloadId));
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<File> fileFor(String downloadId, String fileName) async =>
      File(p.join((await directoryFor(downloadId)).path, fileName));

  /// The 256-bit key all downloads are encrypted under, minted once per
  /// install. Losing it (keystore reset, restore to a new device) makes
  /// existing downloads unreadable — which is the point.
  Future<Uint8List> masterKey() async {
    final cached = _masterKey;
    if (cached != null) return cached;

    final stored = await _storage.read(key: _masterKeyName);
    if (stored != null) {
      final key = Uint8List.fromList(_hexToBytes(stored));
      if (key.length == 32) {
        _masterKey = key;
        return key;
      }
    }

    final random = Random.secure();
    final key = Uint8List.fromList(
        List<int>.generate(32, (_) => random.nextInt(256)));
    await _storage.write(key: _masterKeyName, value: _bytesToHex(key));
    _masterKey = key;
    return key;
  }

  /// Per-download 16-byte nonce, stored alongside the download row. Reusing
  /// one nonce across downloads under the same key would repeat the CTR
  /// keystream, so each gets its own.
  static Uint8List newNonce() {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(_blockSize, (_) => random.nextInt(256)));
  }

  static String bytesToHex(List<int> bytes) => _bytesToHex(bytes);
  static Uint8List hexToBytes(String hex) => Uint8List.fromList(_hexToBytes(hex));

  /// Encrypts [plaintext] and writes it to [fileName] under this download.
  /// Returns the number of bytes written (CTR is a stream cipher, so that's
  /// exactly the plaintext length).
  Future<int> writeSegment({
    required String downloadId,
    required String fileName,
    required Uint8List nonce,
    required int segmentIndex,
    required Uint8List plaintext,
  }) async {
    final cipherText = await _transform(
      data: plaintext,
      nonce: nonce,
      segmentIndex: segmentIndex,
      byteOffset: 0,
    );
    final file = await fileFor(downloadId, fileName);
    await file.writeAsBytes(cipherText, flush: true);
    return cipherText.length;
  }

  /// Reads back a segment, or a byte range of one.
  ///
  /// CTR's seekability is doing the work here: [start] is turned into a
  /// counter offset, so a range request in the middle of a 6 MB segment reads
  /// and decrypts only the bytes asked for.
  Future<Uint8List> readSegment({
    required String downloadId,
    required String fileName,
    required Uint8List nonce,
    required int segmentIndex,
    int start = 0,
    int? end,
  }) async {
    final file = await fileFor(downloadId, fileName);
    final length = await file.length();
    final from = start.clamp(0, length);
    final to = (end ?? length).clamp(from, length);
    if (to <= from) return Uint8List(0);

    final raw = Uint8List.fromList(
        await file.openRead(from, to).expand((chunk) => chunk).toList());

    return _transform(
      data: raw,
      nonce: nonce,
      segmentIndex: segmentIndex,
      byteOffset: from,
    );
  }

  Future<int> segmentSize(String downloadId, String fileName) async {
    final file = await fileFor(downloadId, fileName);
    if (!await file.exists()) return 0;
    return file.length();
  }

  Future<bool> segmentExists(String downloadId, String fileName) async =>
      (await fileFor(downloadId, fileName)).exists();

  /// Total bytes this download occupies on disk.
  Future<int> sizeOf(String downloadId) async {
    final directory = await directoryFor(downloadId);
    if (!await directory.exists()) return 0;

    var total = 0;
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  Future<int> totalSize() async {
    final directory = await root();
    if (!await directory.exists()) return 0;

    var total = 0;
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  Future<void> deleteDownload(String downloadId) async {
    final directory = await directoryFor(downloadId);
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<Uint8List> _transform({
    required Uint8List data,
    required Uint8List nonce,
    required int segmentIndex,
    required int byteOffset,
  }) async {
    if (data.isEmpty) return data;
    return ctrTransform(
      data: data,
      key: await masterKey(),
      nonce: nonce,
      segmentIndex: segmentIndex,
      byteOffset: byteOffset,
    );
  }
}

/// AES-CTR over [data]. Symmetric, so this both encrypts and decrypts.
///
/// The counter block is `nonce XOR (segmentIndex in the low 8 bytes)`,
/// advanced by `byteOffset / 16` blocks. Deriving per-segment counters from a
/// single nonce keeps one stored nonce per download while still giving every
/// segment its own keystream — and makes any byte offset directly
/// addressable, which is what lets the loopback server answer ranged requests
/// without decrypting from the start of the file.
///
/// Top-level (rather than a method) so it can be exercised without a keystore.
Uint8List ctrTransform({
  required Uint8List data,
  required Uint8List key,
  required Uint8List nonce,
  required int segmentIndex,
  int byteOffset = 0,
}) {
  if (data.isEmpty) return data;

  const blockSize = 16;
  final counter = _counterBlock(nonce, segmentIndex, byteOffset ~/ blockSize);

  final cipher = CTRStreamCipher(AESEngine())
    ..init(true, ParametersWithIV(KeyParameter(key), counter));

  // A range starting mid-block must begin at the block boundary with the
  // leading bytes discarded, or the keystream would be misaligned.
  final skew = byteOffset % blockSize;
  if (skew == 0) return cipher.process(data);

  final padded = Uint8List(skew + data.length)
    ..setRange(skew, skew + data.length, data);
  final processed = cipher.process(padded);
  return Uint8List.sublistView(processed, skew);
}

Uint8List _counterBlock(Uint8List nonce, int segmentIndex, int blockOffset) {
  final counter = Uint8List.fromList(nonce);

  // Fold the segment index into the low 8 bytes so each segment starts on its
  // own keystream.
  var index = segmentIndex;
  for (var i = 15; i >= 8 && index != 0; i--) {
    counter[i] ^= index & 0xFF;
    index >>= 8;
  }

  // Then advance by whole blocks for the requested byte offset.
  var carry = blockOffset;
  for (var i = 15; i >= 0 && carry != 0; i--) {
    final sum = counter[i] + (carry & 0xFF);
    counter[i] = sum & 0xFF;
    carry = (carry >> 8) + (sum >> 8);
  }

  return counter;
}

/// Undoes upstream HLS AES-128-CBC encryption at download time, so what
/// lands on disk is plain media under our own key rather than doubly
/// encrypted under a key that expires with the stream. Mirrors
/// `decryptAES128()` in `web/public/scripts/watch.js`.
Uint8List decryptAes128Cbc({
  required Uint8List data,
  required Uint8List key,
  required Uint8List iv,
}) {
  if (data.isEmpty) return data;

  final cipher = CBCBlockCipher(AESEngine())
    ..init(false, ParametersWithIV(KeyParameter(key), iv));

  final output = Uint8List(data.length);
  for (var offset = 0; offset + 16 <= data.length; offset += 16) {
    cipher.processBlock(data, offset, output, offset);
  }

  // Strip PKCS#7 padding, tolerating a stream whose final block isn't padded
  // the way we expect rather than throwing away a whole segment.
  if (output.isEmpty) return output;
  final pad = output.last;
  if (pad >= 1 && pad <= 16 && pad <= output.length) {
    return Uint8List.sublistView(output, 0, output.length - pad);
  }
  return output;
}

const _hexDigits = '0123456789abcdef';

String _bytesToHex(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer
      ..write(_hexDigits[(byte >> 4) & 0x0F])
      ..write(_hexDigits[byte & 0x0F]);
  }
  return buffer.toString();
}

List<int> _hexToBytes(String hex) {
  final bytes = <int>[];
  for (var i = 0; i + 1 < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return bytes;
}
