/// Admin-only server config models, mirroring `services/settings.service.ts`.
/// `shared_secret` is write-only server-side (accepted on create/update,
/// never returned), so it has no field here — only a setter parameter.
class HostingPoint {
  const HostingPoint({
    required this.id,
    required this.name,
    required this.url,
    this.enabled = true,
    this.lastSyncedAt,
    this.lastSyncStatus,
    this.lastSyncError,
  });

  factory HostingPoint.fromJson(Map<String, dynamic> json) {
    return HostingPoint(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      enabled: json['enabled'] != false,
      lastSyncedAt: DateTime.tryParse(json['last_synced_at']?.toString() ?? ''),
      lastSyncStatus: json['last_sync_status']?.toString(),
      lastSyncError: json['last_sync_error']?.toString(),
    );
  }

  final String id;
  final String name;
  final String url;
  final bool enabled;
  final DateTime? lastSyncedAt;
  final String? lastSyncStatus;
  final String? lastSyncError;
}

class SyncSettings {
  const SyncSettings({this.enabled = false, this.intervalMinutes = 15});

  factory SyncSettings.fromJson(Map<String, dynamic> json) {
    return SyncSettings(
      enabled: json['enabled'] == true,
      intervalMinutes: (json['intervalMinutes'] as num?)?.round() ?? 15,
    );
  }

  final bool enabled;
  final int intervalMinutes;

  Map<String, dynamic> toJson() =>
      {'enabled': enabled, 'intervalMinutes': intervalMinutes};

  SyncSettings copyWith({bool? enabled, int? intervalMinutes}) => SyncSettings(
        enabled: enabled ?? this.enabled,
        intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      );
}

class PowerSettings {
  const PowerSettings({
    this.enabled = false,
    this.idleMinutes = 60,
    this.minUptimeMinutes = 30,
  });

  factory PowerSettings.fromJson(Map<String, dynamic> json) {
    return PowerSettings(
      enabled: json['enabled'] == true,
      idleMinutes: (json['idleMinutes'] as num?)?.round() ?? 60,
      minUptimeMinutes: (json['minUptimeMinutes'] as num?)?.round() ?? 30,
    );
  }

  final bool enabled;
  final int idleMinutes;
  final int minUptimeMinutes;

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'idleMinutes': idleMinutes,
        'minUptimeMinutes': minUptimeMinutes,
      };

  PowerSettings copyWith({bool? enabled, int? idleMinutes, int? minUptimeMinutes}) =>
      PowerSettings(
        enabled: enabled ?? this.enabled,
        idleMinutes: idleMinutes ?? this.idleMinutes,
        minUptimeMinutes: minUptimeMinutes ?? this.minUptimeMinutes,
      );
}

/// `GET /api/settings/power/status` — the same `{shouldShutdown, reason}`
/// the host-side power-controller polls, surfaced for the admin panel.
class PowerStatus {
  const PowerStatus({this.shouldShutdown = false, this.reason});

  factory PowerStatus.fromJson(Map<String, dynamic> json) => PowerStatus(
        shouldShutdown: json['shouldShutdown'] == true,
        reason: json['reason']?.toString(),
      );

  final bool shouldShutdown;
  final String? reason;
}

/// `GET /api/cast-config` — receiver app id + the absolute proxy base the
/// Chromecast receiver must use for child manifest URLs.
class CastConfig {
  const CastConfig({required this.castProxyBase, required this.castReceiverAppId});

  factory CastConfig.fromJson(Map<String, dynamic> json) => CastConfig(
        castProxyBase: json['castProxyBase']?.toString() ?? '',
        castReceiverAppId: json['castReceiverAppId']?.toString() ?? '',
      );

  final String castProxyBase;
  final String castReceiverAppId;
}
