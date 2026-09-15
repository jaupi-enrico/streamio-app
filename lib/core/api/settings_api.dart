import '../models/models.dart';
import 'api_client.dart';

/// `routes/settings.router.ts` — the whole router is gated by
/// `requireAuth + requireAdmin` (the `ADMIN_EMAILS` allowlist), so a
/// non-admin account gets a 403 [ApiException] from every call here. The
/// admin tab is hidden unless [isAdmin] succeeds.
class SettingsApi {
  SettingsApi(this._client);

  final ApiClient _client;

  String _seg(String value) => Uri.encodeComponent(value);

  /// There is no "am I an admin" endpoint; the web account page infers it by
  /// probing an admin route and hiding the tab on 403.
  Future<bool> isAdmin() async {
    try {
      await hostingPoints();
      return true;
    } on ApiException catch (err) {
      if (err.isForbidden || err.statusCode == 401) return false;
      rethrow;
    }
  }

  // ── Hosting points ────────────────────────────────────────

  Future<List<HostingPoint>> hostingPoints() async {
    final json = await _client.get<dynamic>('/api/settings/hosting-points',
        authenticated: true);
    final rows = json is List ? json : (json is Map ? json['data'] : null);
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((e) => HostingPoint.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<void> addHostingPoint({
    required String name,
    required String url,
    required String sharedSecret,
    bool enabled = true,
  }) =>
      _client.post<dynamic>(
        '/api/settings/hosting-points',
        authenticated: true,
        body: {
          'name': name,
          'url': url,
          'shared_secret': sharedSecret,
          'enabled': enabled,
        },
      );

  /// `sharedSecret` is write-only server-side: omit it to leave it unchanged.
  Future<void> updateHostingPoint(
    String id, {
    String? name,
    String? url,
    bool? enabled,
    String? sharedSecret,
  }) =>
      _client.put<dynamic>(
        '/api/settings/hosting-points/${_seg(id)}',
        authenticated: true,
        body: {
          if (name != null) 'name': name,
          if (url != null) 'url': url,
          if (enabled != null) 'enabled': enabled,
          if (sharedSecret != null && sharedSecret.isNotEmpty)
            'shared_secret': sharedSecret,
        },
      );

  Future<void> deleteHostingPoint(String id) => _client.delete<dynamic>(
      '/api/settings/hosting-points/${_seg(id)}',
      authenticated: true);

  // ── Sync ──────────────────────────────────────────────────

  Future<SyncSettings> syncSettings() async {
    final json = await _client.get<Map<String, dynamic>>('/api/settings/sync',
        authenticated: true);
    return SyncSettings.fromJson(json);
  }

  Future<void> updateSyncSettings(SyncSettings settings) => _client.put<dynamic>(
        '/api/settings/sync',
        authenticated: true,
        body: settings.toJson(),
      );

  // ── Power ─────────────────────────────────────────────────

  Future<PowerSettings> powerSettings() async {
    final json = await _client.get<Map<String, dynamic>>('/api/settings/power',
        authenticated: true);
    return PowerSettings.fromJson(json);
  }

  Future<void> updatePowerSettings(PowerSettings settings) => _client.put<dynamic>(
        '/api/settings/power',
        authenticated: true,
        body: settings.toJson(),
      );

  Future<PowerStatus> powerStatus() async {
    final json = await _client.get<Map<String, dynamic>>(
        '/api/settings/power/status',
        authenticated: true);
    return PowerStatus.fromJson(json);
  }

  /// Asks the host-side `power-controller` to power the machine off on its
  /// next poll. The server itself runs in Docker and can't do this.
  Future<void> requestShutdown({String? reason}) => _client.post<dynamic>(
        '/api/settings/power/shutdown',
        authenticated: true,
        body: {if (reason != null) 'reason': reason},
      );

  Future<void> cancelShutdown() => _client.post<dynamic>(
      '/api/settings/power/shutdown/cancel',
      authenticated: true);
}
