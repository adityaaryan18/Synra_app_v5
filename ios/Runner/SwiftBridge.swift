import Flutter
import UIKit

@objc public class SwiftBridge: NSObject, FlutterPlugin {
    private let camera = HighSpeedCamera()
    private let registrar: FlutterPluginRegistrar
    
    static var sharedChannel: FlutterMethodChannel?

    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        super.init()
    }

    @objc public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "synra/camera", binaryMessenger: registrar.messenger())
        SwiftBridge.sharedChannel = channel
        
        let instance = SwiftBridge(registrar: registrar)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Extract arguments as a dictionary for easier access
        let args = call.arguments as? [String: Any]

        switch call.method {
            
        case "initializePreview":
            let textureId = camera.setupPreview(registry: self.registrar.textures())
            result(textureId)

        case "setSaveRoot":
            if let path = args?["path"] as? String {
                camera.setSaveRoot(path: path) // This method updates the root URL in HighSpeedCamera
                result(true)
            }

        case "saveVoiceMemo":
            // --- NEW: Handle Voice Memo move ---
            if let path = args?["path"] as? String {
                camera.saveVoiceMemo(tempPath: path)
                result(true)
            } else {
                result(FlutterError(code: "PATH_MISSING", message: "Voice memo path was null", details: nil))
            }

        case "start":
            // --- UPDATED: Extract Name and Description ---
            let fps = args?["fps"] as? Int ?? 120
            let name = args?["name"] as? String ?? "Unnamed"
            let desc = args?["desc"] as? String ?? ""
            
            // Pass metadata to the camera class
            camera.startRecording(fps: fps, name: name, description: desc)
            result(true)
            
        case "setLock":
            // Check if arguments is a Bool (from direct call) or in a Map
            let locked = (call.arguments as? Bool) ?? (args?["locked"] as? Bool) ?? false
            camera.setLock(locked)
            result(true)

        case "stop":
            camera.stopRecording()
            result(true)

        case "updateMetadata":
            if let name = args?["name"] as? String {
                camera.experimentName = name
                camera.experimentDesc = args?["desc"] as? String ?? ""
                camera.createSessionFolder() // Prepare the folder early
                result(true)
            } else {
                result(false)
            }
            
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
                self.camera.updatePressure(pressure)
            }
            result(true)

        case "updateZoom":
            if let zoom = call.arguments as? Double { camera.updateZoom(CGFloat(zoom)) }
            result(true)

        case "restorePermission":
            camera.restoreSavedBookmark()
            result(true)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}