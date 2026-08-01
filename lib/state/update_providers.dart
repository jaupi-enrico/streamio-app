import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/api/version_api.dart';
import '../core/models/models.dart';
import 'api_providers.dart';

final versionApiProvider =
    Provider<VersionApi>((ref) => VersionApi(ref.watch(apiClientProvider)));

/// The server's version policy for this build, fetched once per launch (and
/// again if the user points the app at a different server, since the policy
/// belongs to the server, not the app).
///
/// Deliberately forgiving: an install running an older Streamio has no
/// `/api/version` at all, and a phone with no signal has no answer either.
/// Neither is a reason to bother the user, so both resolve to null and the
/// app carries on exactly as it did before this existed.
final updateCheckProvider = FutureProvider<AppUpdateInfo?>((ref) async {
  try {
    return await ref.watch(versionApiProvider).check();
  } catch (_) {
    return null;
  }
});

/// Set the moment any request comes back 426, and never cleared: once the
/// server is refusing this build, nothing it can do will work again until the
/// user installs a newer one.
class ClientOutdatedNotifier extends StateNotifier<ClientOutdatedException?> {
  ClientOutdatedNotifier() : super(null);

  void report(ClientOutdatedException error) => state = error;
}

final clientOutdatedProvider =
    StateNotifierProvider<ClientOutdatedNotifier, ClientOutdatedException?>((ref) {
  final notifier = ClientOutdatedNotifier();
  try {
    final subscription =
        ref.watch(apiClientProvider).onClientOutdated.listen(notifier.report);
    ref.onDispose(subscription.cancel);
  } on ServerNotConfigured {
    // First run: no server chosen yet, so there is nothing to be rejected by.
    // This provider is rebuilt once one is, because it watches the client.
  }
  return notifier;
});
