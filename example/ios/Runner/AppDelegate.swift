import UIKit
import Flutter
import client_flutter_background_service

func registerPlugins(_ registry: (NSObjectProtocol & FlutterPluginRegistry)?) {
    GeneratedPluginRegistrant.register(with: registry)
}

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    SwiftClientFlutterBackgroundServicePlugin.setPluginRegistrantCallback(registerPlugins(_:))
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
    
}
