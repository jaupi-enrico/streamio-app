import 'package:flutter_riverpod/flutter_riverpod.dart';

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

final contentApiProvider = Provider<ContentApi>((ref) => ContentApi(ref.watch(apiClientProvider)));
final authApiProvider = Provider<AuthApi>((ref) => AuthApi(ref.watch(apiClientProvider)));
final accountApiProvider = Provider<AccountApi>((ref) => AccountApi(ref.watch(apiClientProvider)));
final socialApiProvider = Provider<SocialApi>((ref) => SocialApi(ref.watch(apiClientProvider)));
final roomsApiProvider = Provider<RoomsApi>((ref) => RoomsApi(ref.watch(apiClientProvider)));
final settingsApiProvider = Provider<SettingsApi>((ref) => SettingsApi(ref.watch(apiClientProvider)));
