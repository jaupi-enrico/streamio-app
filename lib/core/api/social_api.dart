import '../models/models.dart';
import 'api_client.dart';

/// `routes/follow.router.ts` + `routes/share.router.ts`, both mounted under
/// `/api/social`.
class SocialApi {
  SocialApi(this._client);

  final ApiClient _client;

  String _seg(String value) => Uri.encodeComponent(value);

  List<T> _list<T>(dynamic json, T Function(Map<String, dynamic>) map) {
    final rows = json is List ? json : (json is Map ? json['data'] : null);
    if (rows is! List) return <T>[];
    return rows
        .whereType<Map>()
        .map((e) => map(e.cast<String, dynamic>()))
        .toList();
  }

  // ── Follows ───────────────────────────────────────────────

  Future<List<FollowSummary>> searchUsers(String query, {int limit = 20}) async {
    final json = await _client.get<dynamic>(
      '/api/social/users/search',
      authenticated: true,
      query: {'query': query, 'q': query, 'limit': limit},
    );
    return _list(json, FollowSummary.fromJson);
  }

  Future<void> follow(String userId) => _client.post<dynamic>(
      '/api/social/follows/${_seg(userId)}',
      authenticated: true);

  Future<void> unfollow(String userId) => _client.delete<dynamic>(
      '/api/social/follows/${_seg(userId)}',
      authenticated: true);

  Future<bool> isFollowing(String userId) async {
    final json = await _client.get<Map<String, dynamic>>(
        '/api/social/follows/${_seg(userId)}/status',
        authenticated: true);
    return json['following'] == true || json['is_following'] == true;
  }

  Future<List<FollowSummary>> followers(String userId) async {
    final json = await _client.get<dynamic>(
        '/api/social/users/${_seg(userId)}/followers',
        authenticated: true);
    return _list(json, FollowSummary.fromJson);
  }

  Future<List<FollowSummary>> following(String userId) async {
    final json = await _client.get<dynamic>(
        '/api/social/users/${_seg(userId)}/following',
        authenticated: true);
    return _list(json, FollowSummary.fromJson);
  }

  /// `{followers, following}` counts for the signed-in user.
  Future<({int followers, int following})> myFollowCounts() async {
    final json = await _client.get<Map<String, dynamic>>(
        '/api/social/me/follow-counts',
        authenticated: true);
    return (
      followers: (json['followers'] as num?)?.round() ?? 0,
      following: (json['following'] as num?)?.round() ?? 0,
    );
  }

  // ── Shares ────────────────────────────────────────────────

  Future<List<Share>> inbox({int limit = 50, int offset = 0}) async {
    final json = await _client.get<dynamic>('/api/social/shares/inbox',
        authenticated: true, query: {'limit': limit, 'offset': offset});
    return _list(json, Share.fromJson);
  }

  Future<List<Share>> sent({int limit = 50, int offset = 0}) async {
    final json = await _client.get<dynamic>('/api/social/shares/sent',
        authenticated: true, query: {'limit': limit, 'offset': offset});
    return _list(json, Share.fromJson);
  }

  Future<int> unreadCount() async {
    final json = await _client.get<Map<String, dynamic>>(
        '/api/social/shares/unread-count',
        authenticated: true);
    return (json['count'] as num?)?.round() ?? 0;
  }

  Future<Share> share(String shareId) async {
    final json = await _client.get<Map<String, dynamic>>(
        '/api/social/shares/${_seg(shareId)}',
        authenticated: true);
    final data = json['data'];
    return Share.fromJson(
        data is Map ? data.cast<String, dynamic>() : json);
  }

  /// Rate-limited server-side (`shareLimiter`) — a 429 surfaces as an
  /// [ApiException] carrying the server's message.
  Future<void> createShare({
    required String provider,
    required String showId,
    required List<String> recipientIds,
    String? episodeId,
    String? episodeLabel,
    int? clipStartSeconds,
    int? clipEndSeconds,
    String? message,
  }) =>
      _client.post<dynamic>(
        '/api/social/shares',
        authenticated: true,
        body: {
          'provider': provider,
          'show_id': showId,
          'recipient_ids': recipientIds,
          if (episodeId != null) 'episode_id': episodeId,
          if (episodeLabel != null) 'episode_label': episodeLabel,
          if (clipStartSeconds != null) 'clip_start_seconds': clipStartSeconds,
          if (clipEndSeconds != null) 'clip_end_seconds': clipEndSeconds,
          if (message != null && message.isNotEmpty) 'message': message,
        },
      );

  Future<void> deleteShare(String shareId) => _client.delete<dynamic>(
      '/api/social/shares/${_seg(shareId)}',
      authenticated: true);

  Future<void> markShareRead(String shareId) => _client.patch<dynamic>(
      '/api/social/shares/${_seg(shareId)}/read',
      authenticated: true);

  /// `emoji` must be one of [kAllowedReactions]; anything else is a 400.
  Future<void> react(String shareId, String emoji) => _client.put<dynamic>(
        '/api/social/shares/${_seg(shareId)}/reaction',
        authenticated: true,
        body: {'emoji': emoji},
      );

  Future<void> removeReaction(String shareId) => _client.delete<dynamic>(
      '/api/social/shares/${_seg(shareId)}/reaction',
      authenticated: true);

  Future<List<ShareReaction>> reactions(String shareId) async {
    final json = await _client.get<dynamic>(
        '/api/social/shares/${_seg(shareId)}/reactions',
        authenticated: true);
    return _list(json, ShareReaction.fromJson);
  }
}
