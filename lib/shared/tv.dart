import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Whether the app is running on a D-pad-only device (Android TV, Google TV,
/// Fire TV).
///
/// [MediaQuery.navigationModeOf] looks like the built-in signal for this, and
/// this file used to be nothing but that call — but `navigationMode` is a
/// value the *application* sets on a [MediaQuery] (it defaults to
/// [NavigationMode.traditional] and no engine ever writes the platform's mode
/// into it). It therefore answered `false` on every device including a real
/// television, which silently disabled every TV code path in the app: the
/// D-pad nav rail never replaced the touch chrome, the player's controls never
/// took initial focus, and so on. The platform answer comes from
/// [TvPlatform.load] instead; the MediaQuery aspect is still honoured so a
/// caller that deliberately wraps a subtree in
/// `MediaQuery(navigationMode: directional)` — or a widget test — still gets
/// the TV treatment.
bool isTv(BuildContext context) =>
    TvPlatform.isTvDevice ||
    MediaQuery.navigationModeOf(context) == NavigationMode.directional;

/// The platform's own answer to "is this a television?", resolved once during
/// startup so [isTv] can stay a synchronous call from `build`.
///
/// Android answers from `UiModeManager` plus the leanback/touchscreen system
/// features (see `MainActivity.kt`); every other platform answers `false`,
/// which is also the fallback when the channel isn't there at all (tests, a
/// plugin registration failure) — being wrong towards "not a TV" only costs
/// the touch chrome on a device that also accepts touch.
class TvPlatform {
  TvPlatform._();

  static const _channel = MethodChannel('streamio/platform');

  static bool _isTv = false;

  static bool get isTvDevice => _isTv;

  static Future<void> load() async {
    try {
      _isTv = await _channel.invokeMethod<bool>('isTv') ?? false;
    } catch (_) {
      _isTv = false;
    }
  }

  @visibleForTesting
  static set debugIsTv(bool value) => _isTv = value;
}
