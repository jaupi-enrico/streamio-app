import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// This build's own version, read once at launch.
///
/// It is loaded eagerly in `main()` rather than awaited per use because
/// [ApiClient] has to stamp `X-Client-Version` on every request from a
/// synchronous constructor. A build that somehow fails to report its version
/// simply omits the header — the server then treats it as older than any
/// floor, which is the safe direction to be wrong in.
class AppVersion {
  AppVersion._();

  static String? _current;

  /// e.g. "1.0.0" — the `version:` from pubspec.yaml without the build number.
  static String? get current => _current;

  /// Tests construct an [ApiClient] without a platform channel to read the
  /// real version from.
  @visibleForTesting
  static set debugCurrent(String? value) => _current = value;

  static Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      _current = version.isEmpty ? null : version;
    } catch (_) {
      // Not fatal: the app works fine, it just can't tell the server which
      // build it is.
      _current = null;
    }
  }
}
