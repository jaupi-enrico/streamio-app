import 'package:flutter/widgets.dart';

/// Whether the app is running on a D-pad-only device (Android TV, Google TV).
///
/// Android reports [NavigationMode.directional] via the platform's
/// `uiMode`/touch-exploration state whenever there's no touch digitizer, which
/// is exactly the signal we want — no plugin or device-model sniffing needed.
bool isTv(BuildContext context) =>
    MediaQuery.navigationModeOf(context) == NavigationMode.directional;
