import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/api/api_client.dart';
import 'core/app_version.dart';
import 'shared/tv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // The type is in `assets/google_fonts/`, so nothing here ever talks to
  // fonts.gstatic.com. It used to: google_fonts' default is to fetch on first
  // use and cache on device, which meant a first launch with no DNS — a plane,
  // a captive portal, a self-hosted install reached over a LAN with no route
  // out — rendered the whole app in Flutter's fallback face. Turning fetching
  // off also makes a missing weight a loud error in development instead of a
  // silent network dependency in production.
  GoogleFonts.config.allowRuntimeFetching = false;
  LicenseRegistry.addLicense(() async* {
    for (final family in ['DMSans', 'BebasNeue']) {
      yield LicenseEntryWithLineBreaks(
        ['google_fonts'],
        await rootBundle.loadString('assets/google_fonts/OFL-$family.txt'),
      );
    }
  });

  // Awaited before the first widget builds: ApiClient stamps X-Client-Version
  // from a synchronous constructor, so the version must be known before
  // anything can construct one, and `isTv()` is read from `build` so the
  // answer has to be in hand before the first frame — a shell that started
  // out as the touch layout and switched a frame later would drop whatever
  // focus the D-pad had just established.
  await Future.wait([AppVersion.load(), TvPlatform.load()]);
  runApp(ProviderScope(retry: _retryTransportFailuresOnly, child: const StreamioApp()));
}

/// Riverpod 3 retries a failing provider by itself — ten times, backing off to
/// 6.4s — which is what you want for a tunnel that blinked and exactly what you
/// don't want for an answer the server meant: `/api/genres/:id` replies 400 when
/// the provider has no genre filter and 403 for an 18+ genre behind a closed
/// gate, and both are rendered in place. Retrying those would sit on a spinner
/// for half a minute and then show the same error, so 4xx (and a dead session,
/// and a build the server refuses) fail immediately and everything else — 5xx,
/// DNS, no signal — keeps the default backoff.
Duration? _retryTransportFailuresOnly(int retryCount, Object error) {
  if (error is SessionExpiredException || error is ClientOutdatedException) {
    return null;
  }
  final status = error is ApiException ? error.statusCode : null;
  if (status != null && status >= 400 && status < 500) return null;

  return ProviderContainer.defaultRetry(retryCount, error);
}
