import '../models/models.dart';
import 'api_client.dart';

/// `routes/version.router.ts` — public and unauthenticated, deliberately: a
/// build too old to sign in still has to be able to find out that it's too
/// old and where to get a newer one. It is also exempt from the server's
/// client-version gate for the same reason, so it answers even when every
/// other endpoint is returning 426.
class VersionApi {
  VersionApi(this._client);

  final ApiClient _client;

  Future<AppUpdateInfo> check() async {
    final json = await _client.get<Map<String, dynamic>>('/api/version');
    return AppUpdateInfo.fromJson(json);
  }
}
