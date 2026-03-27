import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {

    // Store the bridge instance to keep it alive
    var bridge: SwiftBridge?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        // 1. Standard Flutter Plugin Registration
        GeneratedPluginRegistrant.register(with: self)

        // 2. Identify the Flutter View Controller
        guard let controller = window?.rootViewController as? FlutterViewController else {
            return super.application(application, didFinishLaunchingWithOptions: launchOptions)
        }
        
        let messenger = controller.binaryMessenger
        
        // 3. Create the Method Channel (Must match the name in Dart)
        let channel = FlutterMethodChannel(name: "synra/camera", binaryMessenger: messenger)

        // --- THE CRITICAL FIX ---
        // We assign this channel to the static variable in SwiftBridge.
        // This is why your HighSpeedCamera was seeing 'NIL' before.
        SwiftBridge.sharedChannel = channel 
        // ------------------------

        // 4. Initialize the Bridge and set the Handler
        if let registrar = self.registrar(forPlugin: "SwiftBridge") {
            let bridgeInstance = SwiftBridge(registrar: registrar)
            self.bridge = bridgeInstance
            
            channel.setMethodCallHandler { [weak self] (call, result) in
                guard let self = self, let bridge = self.bridge else {
                    result(FlutterMethodNotImplemented)
                    return
                }
                // Route Flutter calls to the SwiftBridge logic
                bridge.handle(call, result: result)
            }
        }
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}