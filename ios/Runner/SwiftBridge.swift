import Flutter
import UIKit

@objc public class SwiftBridge: NSObject, FlutterPlugin {
    private let camera = HighSpeedCamera()
    private let registrar: FlutterPluginRegistrar
    
    // NEW: Static reference so HighSpeedCamera can find the channel
    static var sharedChannel: FlutterMethodChannel?

    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        super.init()
    }

    @objc public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "synra/camera", binaryMessenger: registrar.messenger())
        
        // STORE the channel reference here
        SwiftBridge.sharedChannel = channel
        
        let instance = SwiftBridge(registrar: registrar)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
            
        case "initializePreview":
            let textureId = camera.setupPreview(registry: self.registrar.textures())
            result(textureId)

        case "start":
            let args = call.arguments as? [String: Any]
            let fps = args?["fps"] as? Int ?? 240
            camera.startRecording(fps: fps)
            result(true)
            
        case "setLock":
            if let locked = call.arguments as? Bool {
                camera.setLock(locked)
            }
            result(true)

        case "stop":
            camera.stopRecording()
            result(true)
            
        case "getLidarProfile":
            camera.captureLidarProfile {
                DispatchQueue.main.async { result(true) }
            }
            
        case "updateISO":
            if let iso = call.arguments as? Double { camera.updateISO(Float(iso)) }
            result(true)
            
        case "updateShutter":
            if let shutter = call.arguments as? String { camera.updateShutterSpeed(shutter) }
            result(true)
            
        case "updateFocus":
            if let focus = call.arguments as? Double { camera.updateFocus(Float(focus)) }
            result(true)
            
        case "updateWB":
            if let wbStr = call.arguments as? String {
                let temp = Float(wbStr.replacingOccurrences(of: "K", with: "")) ?? 5500.0
                camera.updateWB(temp)
            }
            result(true)

        case "updatePressure":
            if let pressure = call.arguments as? Double {
                // Explicitly calling the camera instance method
                self.camera.updatePressure(pressure)
            }
            result(true)

        case "updateZoom":
            if let zoom = call.arguments as? Double { camera.updateZoom(CGFloat(zoom)) }
            result(true)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}