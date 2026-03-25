import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {

    var bridge: SwiftBridge?
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        GeneratedPluginRegistrant.register(with: self)

        guard let controller = window?.rootViewController as? FlutterViewController else {
            return super.application(application, didFinishLaunchingWithOptions: launchOptions)
        }
        let messenger = controller.binaryMessenger
        let channel = FlutterMethodChannel(name: "synra/camera", binaryMessenger: messenger)

        if let registrar = self.registrar(forPlugin: "SwiftBridge") {
            self.bridge = SwiftBridge(registrar: registrar)
            
            channel.setMethodCallHandler { [weak self] (call, result) in
                guard let self = self, let bridge = self.bridge else {
                    result(FlutterMethodNotImplemented)
                    return
                }
                bridge.handle(call, result: result)
            }
        }
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}