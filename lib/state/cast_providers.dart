import 'package:flutter_chrome_cast/entities.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/cast/cast_service.dart';
import 'api_providers.dart';

final castServiceProvider = Provider<CastService>((ref) {
  return CastService(ref.watch(contentApiProvider));
});

/// Whether Cast is usable at all: a supported platform, plus a server that
/// answered `/api/cast-config`. False keeps the Cast button hidden entirely.
final castAvailableProvider = FutureProvider<bool>((ref) async {
  if (!CastService.isSupported) return false;
  return ref.watch(castServiceProvider).initialize();
});

final castDevicesProvider = StreamProvider.autoDispose<List<GoogleCastDevice>>((ref) {
  return ref.watch(castServiceProvider).devicesStream;
});

final castSessionProvider = StreamProvider<GoogleCastSession?>((ref) {
  return ref.watch(castServiceProvider).sessionStream;
});
