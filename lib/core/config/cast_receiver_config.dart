import 'package:shared_preferences/shared_preferences.dart';

/// A device-local override for the Chromecast receiver application id.
///
/// Normally the id comes from the server (`GET /api/cast-config`, which serves
/// `CAST_RECEIVER_APP_ID`), because the receiver is part of the deployment.
/// This override exists for the cases where that isn't enough:
///
///  * the person running the app registered their **own** receiver in the
///    Google Cast console and can't (or doesn't want to) change the server's
///    environment to match — a receiver id is tied to a Cast console account,
///    not to the Streamio install;
///  * the deployment is older than `/api/cast-config` and the endpoint 404s;
///  * bisecting a broken receiver against the default media receiver.
///
/// Stored alongside the server URL in `shared_preferences` rather than in the
/// keystore: it is a public identifier, not a secret.
class CastReceiverConfig {
  static const _appIdKey = 'cast_receiver_app_id';

  /// Google Cast application ids are eight uppercase hex digits — that's what
  /// the console issues, and the SDK matches them literally, so a typo'd id
  /// fails as "no devices found" rather than as an error. Rejecting the wrong
  /// shape up front is the only feedback we can give before a real cast.
  static final _appIdPattern = RegExp(r'^[0-9A-F]{8}$');

  /// Canonicalizes what someone actually pastes (lowercase hex, stray spaces)
  /// and returns null if it can't be a Cast app id.
  static String? normalize(String input) {
    final text = input.trim().toUpperCase();
    if (!_appIdPattern.hasMatch(text)) return null;
    return text;
  }

  static bool isValid(String input) => normalize(input) != null;

  /// The stored override, or null to defer to the server.
  static Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_appIdKey);
    if (stored == null || stored.isEmpty) return null;
    return stored;
  }

  /// [appId] must already be normalized.
  static Future<void> write(String appId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appIdKey, appId);
  }

  /// Drops the override; the server's id applies again.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_appIdKey);
  }
}
