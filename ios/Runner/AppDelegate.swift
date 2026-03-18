import UIKit
import Flutter
    
@main
@objc class AppDelegate: FlutterAppDelegate {
  
  // We hold the bridge here to ensure it doesn't get garbage collected
  var bridge: SwiftBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    let controller = window?.rootViewController as! FlutterViewController
    let messenger = controller.binaryMessenger
    
    // MANUAL REGISTRATION
    let channel = FlutterMethodChannel(name: "synra/camera", binaryMessenger: messenger)
    
    // We need a way to get the registrar manually
    if let registrar = self.registrar(forPlugin: "SwiftBridge") {
        self.bridge = SwiftBridge(registrar: registrar)
        channel.setMethodCallHandler { [weak self] (call, result) in
            self?.bridge?.handle(call, result: result)
        }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
