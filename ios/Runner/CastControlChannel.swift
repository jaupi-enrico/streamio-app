import Flutter
import GoogleCast

/// The `urn:x-cast:com.streamio.control` channel, for
/// lib/core/cast/cast_control_channel.dart. The Android half is
/// `android/app/src/main/kotlin/com/streamio/streamio/CastControlChannel.kt`
/// and the protocol is `docs/protocol.md` in the `cast-receiver` repo.
///
/// This exists because **flutter_chrome_cast has no custom-namespace API at
/// all** — not in Dart, not in its Kotlin, not in its Swift. Everything else
/// the cast panel needs (play/pause, relative seek, active track ids, media
/// status) the plugin does expose and is driven from Dart.
///
/// Two things this must get right:
///
///  * **Re-attach on every session.** A `GCKGenericChannel` belongs to a
///    session, not to the session manager, so it dies with the session. A cast
///    resumed from Control Center — or from another sender — would otherwise
///    leave the panel connected to nothing, which looks exactly like a receiver
///    that stopped answering.
///  * **Never throw at Dart.** Every message is advisory on both sides (the
///    device may be running a receiver older than this build). No session, no
///    channel, a send that fails: all no-ops. A cast that plays must not be
///    breakable by a control that isn't there.
final class CastControlChannel: NSObject {

  private static let namespace = "urn:x-cast:com.streamio.control"
  private static let methodChannel = "streamio/cast_control"
  private static let eventChannel = "streamio/cast_control/events"

  private var events: FlutterEventSink?
  private var channel: GCKGenericChannel?
  private weak var attached: GCKCastSession?

  init(messenger: FlutterBinaryMessenger) {
    super.init()

    FlutterMethodChannel(name: Self.methodChannel, binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "send":
          self?.send(call.arguments as? String)
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

    FlutterEventChannel(name: Self.eventChannel, binaryMessenger: messenger)
      .setStreamHandler(self)
  }

  // MARK: - Session tracking

  private func listen() {
    let manager = GCKCastContext.sharedInstance().sessionManager
    manager.add(self)
    // A session may already be running — the app can be reopened onto one.
    if let session = manager.currentCastSession {
      attach(session)
    }
  }

  private func stopListening() {
    detach()
    GCKCastContext.sharedInstance().sessionManager.remove(self)
  }

  private func attach(_ session: GCKCastSession) {
    if attached === session { return }
    detach()

    let generic = GCKGenericChannel(namespace: Self.namespace)
    generic.delegate = self
    session.add(generic)
    channel = generic
    attached = session
  }

  private func detach() {
    if let generic = channel, let session = attached {
      session.remove(generic)
    }
    channel = nil
    attached = nil
  }

  private func send(_ json: String?) {
    guard let json = json, let generic = channel, generic.isConnected else { return }
    // The throwing overload reports "not connected" and oversized payloads.
    // Both mean the message is gone, which is the correct outcome for an
    // advisory protocol — the next STATE resyncs the panel regardless.
    try? generic.sendTextMessage(json)
  }
}

// MARK: - GCKGenericChannelDelegate

extension CastControlChannel: GCKGenericChannelDelegate {
  func cast(
    _ channel: GCKGenericChannel,
    didReceiveTextMessage message: String,
    withNamespace protocolNamespace: String
  ) {
    guard protocolNamespace == Self.namespace else { return }
    events?(message)
  }
}

// MARK: - GCKSessionManagerListener

extension CastControlChannel: GCKSessionManagerListener {
  func sessionManager(
    _ sessionManager: GCKSessionManager,
    didStart session: GCKCastSession
  ) {
    attach(session)
  }

  func sessionManager(
    _ sessionManager: GCKSessionManager,
    didResumeCastSession session: GCKCastSession
  ) {
    attach(session)
  }

  func sessionManager(
    _ sessionManager: GCKSessionManager,
    didEnd session: GCKSession,
    withError error: Error?
  ) {
    detach()
  }

  func sessionManager(
    _ sessionManager: GCKSessionManager,
    didSuspend session: GCKSession,
    with reason: GCKConnectionSuspendReason
  ) {
    detach()
  }
}

// MARK: - FlutterStreamHandler

extension CastControlChannel: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
    events = eventSink
    listen()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    events = nil
    stopListening()
    return nil
  }
}
