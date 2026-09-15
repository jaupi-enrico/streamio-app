/// The account row returned by `GET /api/account/me`.
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    this.displayName,
    this.avatarUrl,
    this.emailVerified = false,
    this.createdAt,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      displayName: json['display_name']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
      emailVerified: json['email_verified'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }

  /// Round-trips through [AppUser.fromJson], so the keys are the backend's
  /// snake_case ones rather than a second, app-only shape.
  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'email_verified': emailVerified,
        'created_at': createdAt?.toIso8601String(),
      };

  final String id;
  final String email;
  final String? displayName;
  final String? avatarUrl;
  final bool emailVerified;
  final DateTime? createdAt;

  String get label => displayName?.trim().isNotEmpty == true ? displayName! : email;

  /// First letter for the avatar placeholder, matching account.html's
  /// `.hero-avatar` initial.
  String get initial => label.isNotEmpty ? label[0].toUpperCase() : '?';
}
