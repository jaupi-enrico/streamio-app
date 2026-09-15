/// `GET /api/version` — the server's build plus its policy for native clients.
///
/// The server does the version comparison itself (it receives
/// `X-Client-Version` on every request), so [updateAvailable] and
/// [updateRequired] arrive already decided; the app never re-implements
/// semver. Both are null when this build didn't report its version.
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.serverVersion,
    required this.serverCommit,
    required this.apiVersion,
    required this.latest,
    required this.minSupported,
    required this.downloadUrl,
    required this.notes,
    required this.currentVersion,
    required this.updateAvailable,
    required this.updateRequired,
    required this.enforced,
  });

  final String serverVersion;
  final String serverCommit;
  final int apiVersion;

  /// Newest published client build, or null if the server has no policy set.
  final String? latest;

  /// Oldest client build the server still accepts.
  final String? minSupported;
  final String? downloadUrl;
  final String? notes;

  /// The version this build reported, echoed back.
  final String? currentVersion;

  /// Newer build exists — worth prompting about.
  final bool? updateAvailable;

  /// Below [minSupported] — this build is on borrowed time, and is already
  /// being refused if [enforced] is true.
  final bool? updateRequired;

  /// Whether the server is actually blocking outdated builds right now.
  final bool enforced;

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    final server = (json['server'] as Map?)?.cast<String, dynamic>() ?? const {};
    final api = (json['api'] as Map?)?.cast<String, dynamic>() ?? const {};
    final client = (json['client'] as Map?)?.cast<String, dynamic>() ?? const {};

    String? str(Object? value) {
      final text = value?.toString().trim();
      return (text == null || text.isEmpty) ? null : text;
    }

    return AppUpdateInfo(
      serverVersion: str(server['version']) ?? 'unknown',
      serverCommit: str(server['commit']) ?? 'unknown',
      apiVersion: (api['version'] as num?)?.toInt() ?? 1,
      latest: str(client['latest']),
      minSupported: str(client['minSupported']),
      downloadUrl: str(client['downloadUrl']),
      notes: str(client['notes']),
      currentVersion: str(client['current']),
      updateAvailable: client['updateAvailable'] as bool?,
      updateRequired: client['updateRequired'] as bool?,
      enforced: client['enforced'] == true,
    );
  }

  /// Only worth interrupting the user for when there's somewhere to send them.
  bool get shouldPrompt => updateAvailable == true && downloadUrl != null;

  /// Blocked right now — not merely "should update eventually".
  bool get isBlocked => updateRequired == true && enforced;
}
