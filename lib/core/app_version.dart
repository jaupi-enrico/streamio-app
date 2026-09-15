import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// This build's own version, reported to the server as `X-Client-Version` so
/// it can decide whether this build is current (see `GET /api/version`).
///
/// Read from the built artifact rather than a constant in source, so it can't
/// drift from what was actually shipped. `package_info_plus` is already in the
/// dependency tree via `media_kit_video -> wakelock_plus`, so this costs
/// nothing at the native layer.
///
/// Loaded eagerly in `main()` rather than awaited per use, because
/// [ApiClient] stamps the header from a synchronous constructor. A build that
/// somehow fails to report its version omits the header, and the server then
/// treats it as older than any floor — the safe direction to be wrong in.
class AppVersion {
  AppVersion._();

  static String? _current;

  /// e.g. "1.0.0" — pubspec's `version:` without the build number.
  static String? get current => _current;

  static Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      _current = version.isEmpty ? null : version;
    } catch (_) {
      // No platform channel (tests, or a plugin registration failure). Not
      // fatal — the app works, it just can't say which build it is.
      _current = null;
    }
  }

  /// Tests construct an [ApiClient] with no platform channel to read from.
  @visibleForTesting
  static set debugCurrent(String? value) => _current = value;

  @visibleForTesting
  static void debugReset() => _current = null;
}
