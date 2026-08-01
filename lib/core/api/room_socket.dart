import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/models.dart';
import 'api_client.dart';

/// Realtime watch-party channel — the Dart counterpart of `RoomConnection` in
/// `web/public/scripts/room-sync.js`.
///
/// Connects to `wss://…/ws/rooms/:code?token=<access token>`. The token goes
/// in the query string because a WebSocket handshake can't carry an
/// Authorization header; `server.ts` verifies it (and room membership) during
/// the HTTP upgrade, before the socket is accepted.
class RoomConnection {
  RoomConnection({required ApiClient client, required String code})
      : _client = client,
        code = code.toUpperCase();

  final ApiClient _client;
  final String code;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  int _attempts = 0;
  bool _closedByUs = false;
  bool _renewedForReconnect = false;

  final _stateUpdates = StreamController<RoomState>.broadcast();
  final _members = StreamController<List<RoomMember>>.broadcast();
  final _closedByOwner = StreamController<void>.broadcast();
  final _connected = StreamController<bool>.broadcast();

  /// Another member's play/pause/seek/episode change.
  Stream<RoomState> get stateUpdates => _stateUpdates.stream;

  /// Someone joined or left.
  Stream<List<RoomMember>> get memberUpdates => _members.stream;

  /// The owner closed the room (or it was reaped for being empty).
  Stream<void> get closed => _closedByOwner.stream;

  Stream<bool> get connectionState => _connected.stream;

  Future<void> connect() async {
    _closedByUs = false;

    // A reconnect may be failing on the token rather than on the network: the
    // handshake carries the access token, it lives 15 minutes, and a watch
    // party outlasts that easily. The socket has no way to retry a rejected
    // handshake the way a request retries a 401, so the token is renewed here
    // — once per reconnect sequence, not on every backoff attempt.
    if (_attempts > 0 && !_renewedForReconnect) {
      _renewedForReconnect = true;
      await _client.renewAccessToken();
    }

    final token = await _client.tokens.accessToken;
    if (token == null) {
      _connected.add(false);
      return;
    }

    final url = _client.webSocketUrl(
        '/ws/rooms/${Uri.encodeComponent(code)}?token=${Uri.encodeComponent(token)}');

    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channel = channel;

      _subscription = channel.stream.listen(
        _onMessage,
        onDone: _onDone,
        onError: (_) {
          // onDone fires right after; reconnection is handled there so it
          // isn't scheduled twice.
        },
        cancelOnError: false,
      );

      _attempts = 0;
      _connected.add(true);
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    // Traffic on the socket is the only proof the handshake was accepted, so
    // this is where a renewed token is allowed again for the next outage.
    _renewedForReconnect = false;

    Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(raw as String);
      if (decoded is! Map) return;
      message = decoded.cast<String, dynamic>();
    } catch (_) {
      return;
    }

    switch (message['type']) {
      case 'state':
      case 'state_update':
        final payload = message['payload'] ?? message['state'];
        if (payload is Map) {
          _stateUpdates.add(RoomState.fromJson(payload.cast<String, dynamic>()));
        }
      case 'presence':
      case 'members':
        final members = message['members'] ?? message['payload'];
        if (members is List) {
          _members.add(members
              .whereType<Map>()
              .map((m) => RoomMember.fromJson(m.cast<String, dynamic>()))
              .toList());
        }
      case 'closed':
        _closedByUs = true;
        _closedByOwner.add(null);
    }
  }

  void _onDone() {
    _connected.add(false);
    if (_closedByUs) return;
    _scheduleReconnect();
  }

  /// Exponential backoff capped at 15s, matching the web client.
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final delayMs = (1000 * (1 << _attempts)).clamp(1000, 15000);
    _attempts++;
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), connect);
  }

  /// Broadcasts a local change. The server persists it and relays it to the
  /// rest of the room as `state_update`.
  void sendState({
    String? provider,
    String? showId,
    String? episodeId,
    String? episodeLabel,
    String? contentType,
    bool? playing,
    int? positionSeconds,
  }) {
    final channel = _channel;
    if (channel == null) return;

    final payload = <String, dynamic>{
      if (provider != null) 'provider': provider,
      if (showId != null) 'showId': showId,
      if (episodeId != null) 'episodeId': episodeId,
      if (episodeLabel != null) 'episodeLabel': episodeLabel,
      if (contentType != null) 'contentType': contentType,
      if (playing != null) 'playing': playing,
      if (positionSeconds != null) 'positionSeconds': positionSeconds,
    };
    if (payload.isEmpty) return;

    try {
      channel.sink.add(jsonEncode({'type': 'state', 'payload': payload}));
    } catch (_) {
      // The socket died between the check and the send; the reconnect path
      // will pick it up.
    }
  }

  Future<void> dispose() async {
    _closedByUs = true;
    _reconnectTimer?.cancel();
    await _subscription?.cancel();
    await _channel?.sink.close();
    await _stateUpdates.close();
    await _members.close();
    await _closedByOwner.close();
    await _connected.close();
  }
}
