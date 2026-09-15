import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Held for the process's lifetime: the channel is the only owner of the
  /// GCKSessionManager listener, and letting it deallocate would silently stop
  /// the cast panel from receiving anything.
  private var castControl: CastControlChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    castControl = CastControlChannel(messenger: engineBridge.binaryMessenger)
  }
}
