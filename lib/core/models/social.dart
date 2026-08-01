// Social graph + share models, mirroring `services/follow.service.ts`'s
// `UserSummary`/`FollowSummary` and `services/share.service.ts`'s
// `ShareSummary`/`ShareDetail`/`ReactionSummary` row shapes.

/// The emoji set `share.service.ts` accepts; anything else is rejected 400.
const kAllowedReactions = <String>['👍', '❤️', '😂', '😮', '😢', '🔥'];

class UserSummary {
  const UserSummary({required this.id, this.displayName, this.avatarUrl});

  factory UserSummary.fromJson(Map<String, dynamic> json) {
    return UserSummary(
      id: json['id']?.toString() ?? '',
      displayName: json['display_name']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
    );
  }

  final String id;
  final String? displayName;
  final String? avatarUrl;

  String get label =>
      displayName?.trim().isNotEmpty == true ? displayName! : 'User';
  String get initial => label.isNotEmpty ? label[0].toUpperCase() : '?';
}

/// A user in a follower/following list — a [UserSummary] plus whether the
/// current user follows them (used to render the follow/unfollow button
/// without a second round-trip).
class FollowSummary extends UserSummary {
  const FollowSummary({
    required super.id,
    super.displayName,
    super.avatarUrl,
    this.isFollowing = false,
    this.followedAt,
  });

  factory FollowSummary.fromJson(Map<String, dynamic> json) {
    return FollowSummary(
      id: json['id']?.toString() ?? '',
      displayName: json['display_name']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
      isFollowing: json['is_following'] == true || json['following'] == true,
      followedAt: DateTime.tryParse(json['followed_at']?.toString() ?? ''),
    );
  }

  final bool isFollowing;
  final DateTime? followedAt;
}

class ShareReaction {
  const ShareReaction({required this.user, required this.emoji, this.createdAt});

  factory ShareReaction.fromJson(Map<String, dynamic> json) {
    return ShareReaction(
      user: UserSummary.fromJson(
          (json['user'] as Map?)?.cast<String, dynamic>() ?? const {}),
      emoji: json['emoji']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }

  final UserSummary user;
  final String emoji;
  final DateTime? createdAt;
}

class ShareRecipient extends UserSummary {
  const ShareRecipient({
    required super.id,
    super.displayName,
    super.avatarUrl,
    this.readAt,
  });

  factory ShareRecipient.fromJson(Map<String, dynamic> json) {
    return ShareRecipient(
      id: json['id']?.toString() ?? '',
      displayName: json['display_name']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
      readAt: DateTime.tryParse(json['read_at']?.toString() ?? ''),
    );
  }

  final DateTime? readAt;
}

class Share {
  const Share({
    required this.id,
    required this.sender,
    required this.provider,
    required this.showId,
    this.episodeId,
    this.episodeLabel,
    this.clipStartSeconds,
    this.clipEndSeconds,
    this.message,
    this.createdAt,
    this.readAt,
    this.recipients = const [],
    this.reactions = const [],
    this.reactionCount = 0,
  });

  factory Share.fromJson(Map<String, dynamic> json) {
    final recipients = (json['recipients'] as List?)
            ?.whereType<Map>()
            .map((r) => ShareRecipient.fromJson(r.cast<String, dynamic>()))
            .toList() ??
        const <ShareRecipient>[];
    final reactions = (json['reactions'] as List?)
            ?.whereType<Map>()
            .map((r) => ShareReaction.fromJson(r.cast<String, dynamic>()))
            .toList() ??
        const <ShareReaction>[];

    return Share(
      id: json['id']?.toString() ?? '',
      sender: UserSummary.fromJson(
          (json['sender'] as Map?)?.cast<String, dynamic>() ?? const {}),
      provider: json['provider']?.toString() ?? '',
      showId: json['show_id']?.toString() ?? '',
      episodeId: json['episode_id']?.toString(),
      episodeLabel: json['episode_label']?.toString(),
      clipStartSeconds: (json['clip_start_seconds'] as num?)?.round(),
      clipEndSeconds: (json['clip_end_seconds'] as num?)?.round(),
      message: json['message']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      readAt: DateTime.tryParse(json['read_at']?.toString() ?? ''),
      recipients: recipients,
      reactions: reactions,
      reactionCount: (json['reaction_count'] as num?)?.round() ?? reactions.length,
    );
  }

  final String id;
  final UserSummary sender;
  final String provider;
  final String showId;
  final String? episodeId;
  final String? episodeLabel;
  final int? clipStartSeconds;
  final int? clipEndSeconds;
  final String? message;
  final DateTime? createdAt;
  final DateTime? readAt;
  final List<ShareRecipient> recipients;
  final List<ShareReaction> reactions;
  final int reactionCount;

  bool get isUnread => readAt == null;
  bool get isClip => clipStartSeconds != null;
}
