import 'social.dart';

/// Watch-party models, mirroring `services/room.service.ts`'s `RoomDetail` /
/// `RoomState` / `RoomMemberSummary` (camelCase on the wire — the service
/// maps its snake_case row before responding).
class RoomState {
  const RoomState({
    required this.provider,
    required this.showId,
    this.episodeId,
    this.episodeLabel,
    this.contentType = 'episode',
    this.playing = false,
    this.positionSeconds = 0,
    this.updatedAt,
  });

  factory RoomState.fromJson(Map<String, dynamic> json) {
    return RoomState(
      provider: json['provider']?.toString() ?? '',
      showId: json['showId']?.toString() ?? '',
      episodeId: json['episodeId']?.toString(),
      episodeLabel: json['episodeLabel']?.toString(),
      contentType: json['contentType']?.toString() ?? 'episode',
      playing: json['playing'] == true,
      positionSeconds: (json['positionSeconds'] as num?)?.toDouble().round() ?? 0,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }

  final String provider;
  final String showId;
  final String? episodeId;
  final String? episodeLabel;
  final String contentType;
  final bool playing;
  final int positionSeconds;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
        'provider': provider,
        'showId': showId,
        'episodeId': episodeId,
        'episodeLabel': episodeLabel,
        'contentType': contentType,
        'playing': playing,
        'positionSeconds': positionSeconds,
      };
}

class RoomMember extends UserSummary {
  const RoomMember({
    required super.id,
    super.displayName,
    super.avatarUrl,
    this.isOwner = false,
  });

  factory RoomMember.fromJson(Map<String, dynamic> json) {
    return RoomMember(
      id: json['id']?.toString() ?? '',
      displayName: json['display_name']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
      isOwner: json['is_owner'] == true,
    );
  }

  final bool isOwner;
}

class Room {
  const Room({
    required this.id,
    required this.code,
    required this.ownerId,
    required this.state,
    this.members = const [],
    this.isMember = false,
    this.createdAt,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      ownerId: json['ownerId']?.toString() ?? '',
      state: RoomState.fromJson(
          (json['state'] as Map?)?.cast<String, dynamic>() ?? const {}),
      members: (json['members'] as List?)
              ?.whereType<Map>()
              .map((m) => RoomMember.fromJson(m.cast<String, dynamic>()))
              .toList() ??
          const <RoomMember>[],
      isMember: json['isMember'] == true,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    );
  }

  final String id;
  final String code;
  final String ownerId;
  final RoomState state;
  final List<RoomMember> members;
  final bool isMember;
  final DateTime? createdAt;
}
