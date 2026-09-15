import 'package:flutter_riverpod/flutter_riverpod.dart';
// `ProviderException` isn't in the main entrypoint as of Riverpod 3.
import 'package:flutter_riverpod/misc.dart';

import '../core/api/account_api.dart';
import '../core/api/api_client.dart';
import '../core/api/auth_api.dart';
import '../core/api/content_api.dart';
import '../core/api/rooms_api.dart';
import '../core/api/settings_api.dart';
import '../core/api/social_api.dart';
import '../core/api/token_store.dart';
import 'server_config_provider.dart';

/// Thrown when something asks for the API before a server has been chosen.
/// The router keeps this unreachable in practice (it redirects to /setup),
/// so seeing it means a screen was built outside the guarded shell.
class ServerNotConfigured implements Exception {
  const ServerNotConfigured();
  @override
  String toString() => 'No server configured';
}

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

/// Rebuilt whenever the base URL changes; the old client is disposed with it.
final apiClientProvider = Provider<ApiClient>((ref) {
  final baseUrl = ref.watch(currentServerUrlProvider);
  if (baseUrl == null) throw const ServerNotConfigured();

  final client = ApiClient(baseUrl: baseUrl, tokens: ref.watch(tokenStoreProvider));
  ref.onDispose(client.dispose);
  return client;
});

/// [apiClientProvider], but `null` rather than a throw when no server has been
/// chosen yet — for the few providers that legitimately run before /setup.
///
/// Riverpod 3 wraps whatever a provider threw in a [ProviderException] before
/// rethrowing it at the reader, so `on ServerNotConfigured` at the call site
/// quietly stopped matching. This is the one place that unwraps it.
ApiClient? watchApiClientOrNull(Ref ref) =>
    _clientOrNull(() => ref.watch(apiClientProvider));

/// The `ref.read` counterpart of [watchApiClientOrNull].
ApiClient? readApiClientOrNull(Ref ref) =>
    _clientOrNull(() => ref.read(apiClientProvider));

ApiClient? _clientOrNull(ApiClient Function() get) {
  try {
    return get();
  } on ProviderException catch (err) {
    if (err.exception is ServerNotConfigured) return null;
    rethrow;
  } on ServerNotConfigured {
    return null;
  }
}

final contentApiProvider = Provider<ContentApi>((ref) => ContentApi(ref.watch(apiClientProvider)));
final authApiProvider = Provider<AuthApi>((ref) => AuthApi(ref.watch(apiClientProvider)));
final accountApiProvider = Provider<AccountApi>((ref) => AccountApi(ref.watch(apiClientProvider)));
final socialApiProvider = Provider<SocialApi>((ref) => SocialApi(ref.watch(apiClientProvider)));
final roomsApiProvider = Provider<RoomsApi>((ref) => RoomsApi(ref.watch(apiClientProvider)));
final settingsApiProvider = Provider<SettingsApi>((ref) => SettingsApi(ref.watch(apiClientProvider)));
