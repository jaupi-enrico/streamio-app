import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

/// The Streamio control namespace. Must match `NS` in the receiver's
/// `index.html` and `CAST_NS` in the web sender's `watch.js`.
const String kCastControlNamespace = 'urn:x-cast:com.streamio.control';

/// Sender half of `urn:x-cast:com.streamio.control`.
///
/// This is a platform channel rather than a plugin call because
/// **flutter_chrome_cast exposes no custom-namespace API** — there is no
/// `sendMessage` anywhere in its Dart, Kotlin or Swift. Everything the cast
/// panel needs that *is* standard Cast (play/pause, relative seek, active
/// track ids, media status) goes through the plugin from [CastService]; only
/// the Streamio protocol comes through here. The native halves are
/// `android/app/src/main/kotlin/com/streamio/streamio/CastControlChannel.kt`
/// and `ios/Runner/CastControlChannel.swift`.
///
/// The protocol is documented in `docs/protocol.md` in the `cast-receiver`
/// repo. **Every message is advisory in both directions**: a Chromecast may be
/// running a receiver cached from before a message existed, and this app may be
/// older than the receiver it is talking to. Nothing here throws on a message
/// that goes nowhere.
class CastControlChannel {
  CastControlChannel._();

  static final CastControlChannel instance = CastControlChannel._();

  static const MethodChannel _method = MethodChannel('streamio/cast_control');
  static const EventChannel _events = EventChannel('streamio/cast_control/events');

  Stream<Map<String, dynamic>>? _messages;

  /// Messages from the receiver, already decoded. Malformed payloads are
  /// dropped rather than surfaced as stream errors: a control channel that
  /// tears down because one message was odd is worse than one that misses it.
  ///
  /// Broadcast, so the panel and the history writer can both listen. The
  /// native side attaches its session listener on the first subscription and
  /// detaches on the last, so an app that never opens the panel costs nothing.
  Stream<Map<String, dynamic>> get messages {
    return _messages ??= _events
        .receiveBroadcastStream()
        // An error from the platform — no native half at all (desktop, a
        // build without it), or a failure raised by the Cast SDK — must not
        // reach the provider. A `StreamProvider` that ends in error stays in
        // error, so one bad moment would take the panel's *identity* half down
        // for the rest of the process: no title, no duration, no track lists,
        // silently and permanently. Dropping it leaves the stream quiet
        // instead, which is a state every reader already handles (a receiver
        // too old to speak this protocol looks exactly the same), and the
        // transport half never depended on this channel in the first place.
        .handleError(_reportChannelError)
        .map(_decode)
        .where((message) => message != null)
        .cast<Map<String, dynamic>>()
        .asBroadcastStream();
  }

  static bool _errorReported = false;

  /// Once per process: this fails for a structural reason (no native half, no
  /// Cast SDK), not a transient one, so repeating it every reconnect would
  /// only bury it.
  static void _reportChannelError(Object error) {
    if (_errorReported) return;
    _errorReported = true;
    debugPrint('[cast] control channel unavailable ($error) — the panel will '
        'run on the standard Cast channel alone.');
  }

  static Map<String, dynamic>? _decode(dynamic event) {
    if (event is! String) return null;
    try {
      final decoded = jsonDecode(event);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Fire-and-forget. A missing session, a platform without Cast, a send that
  /// races a disconnect: all silently do nothing.
  Future<void> send(Map<String, dynamic> payload) async {
    try {
      await _method.invokeMethod<void>('send', jsonEncode(payload));
    } on MissingPluginException {
      // Desktop, or a build without the native half.
    } on PlatformException {
      // No session, or it ended mid-call.
    }
  }
}
