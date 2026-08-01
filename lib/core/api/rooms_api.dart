import '../models/models.dart';
import 'api_client.dart';

/// `routes/room.router.ts` — watch-party membership and the shared
/// "now playing" state. The realtime half is core/api/room_socket.dart.
class RoomsApi {
  RoomsApi(this._client);

  final ApiClient _client;

  String _seg(String value) => Uri.encodeComponent(value);

  Room _room(dynamic json) {
    if (json is! Map) {
      throw const ApiException('Malformed room response.');
    }
    final map = json.cast<String, dynamic>();
    final data = map['data'] ?? map['room'];
    return Room.fromJson(data is Map ? data.cast<String, dynamic>() : map);
  }

  Future<Room> create({
    required String provider,
    required String showId,
    String? episodeId,
    String? episodeLabel,
    String contentType = 'episode',
  }) async {
    final json = await _client.post<dynamic>(
      '/api/rooms',
      authenticated: true,
      body: {
        'provider': provider,
        'showId': showId,
        if (episodeId != null) 'episodeId': episodeId,
        if (episodeLabel != null) 'episodeLabel': episodeLabel,
        'contentType': contentType,
      },
    );
    return _room(json);
  }

  Future<List<Room>> mine() async {
    final json = await _client.get<dynamic>('/api/rooms/mine', authenticated: true);
    final rows = json is List ? json : (json is Map ? json['data'] : null);
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((e) => Room.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<Room> get(String code) async {
    final json = await _client.get<dynamic>('/api/rooms/${_seg(code)}',
        authenticated: true);
    return _room(json);
  }

  Future<Room> join(String code) async {
    final json = await _client.post<dynamic>('/api/rooms/${_seg(code)}/join',
        authenticated: true);
    return _room(json);
  }

  Future<void> leave(String code) => _client.post<dynamic>(
      '/api/rooms/${_seg(code)}/leave',
      authenticated: true);

  /// Owner-only.
  Future<void> close(String code) =>
      _client.delete<dynamic>('/api/rooms/${_seg(code)}', authenticated: true);
}
