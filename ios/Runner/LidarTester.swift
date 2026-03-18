import AVFoundation
import UIKit
import CoreLocation

class LidarTester: NSObject, AVCaptureDepthDataOutputDelegate, CLLocationManagerDelegate {
    
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "lidar.raw.queue")
    private let depthOutput = AVCaptureDepthDataOutput()
    
    private let locationManager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var currentSessionURL: URL?
    
    // Safety flag to ensure only one capture per run
    private var isCapturing = false
    
    private let mmPerPixelUnit: Float = 25.0
    private var distanceToIntensityLUT: [UInt16] = []

    override init() {
        super.init()
        setupLUT()
        setupLocation()
    }

    private func setupLUT() {
        distanceToIntensityLUT = (0...10000).map { mm in
            let calibrated = Float(mm) / mmPerPixelUnit
            return UInt16(clamping: Int(calibrated))
        }
    }
    
    private func setupLocation() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    private func createSessionFolder() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let folderName = "TestSession_\(formatter.string(from: Date()))"
        let folderURL = docs.appendingPathComponent(folderName)
        
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        self.currentSessionURL = folderURL
    }
    
    func runTestCapture() {
        createSessionFolder()
        isCapturing = true // Set flag
        queue.async {
            self.setupSession()
            self.session.startRunning()
        }
    }
    
    private func setupSession() {
        session.beginConfiguration()
        guard let device = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) else { return }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
            
            depthOutput.isFilteringEnabled = true
            depthOutput.setDelegate(self, callbackQueue: queue)
            if session.canAddOutput(depthOutput) { session.addOutput(depthOutput) }
            
            session.commitConfiguration()
        } catch { print("Setup failed") }
    }
    
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        // Only process the first frame received
        guard isCapturing else { return }
        isCapturing = false
        
        let depthMap = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32).depthDataMap
        processAndSaveRaw(depthMap)
        
        // Stop session immediately after first capture
        session.stopRunning()
    }
    
    private func processAndSaveRaw(_ pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
              let sessionURL = currentSessionURL else { return }
        
        var rawData = [UInt16](repeating: 0, count: width * height)
        
        for y in 0..<height {
            let rowPtr = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float32.self)
            for x in 0..<width {
                let distanceMeters = rowPtr[x]
                if distanceMeters.isFinite && distanceMeters > 0 {
                    let mm = Int(distanceMeters * 1000.0)
                    if mm < distanceToIntensityLUT.count {
                        rawData[y * width + x] = distanceToIntensityLUT[mm]
                    }
                }
            }
        }
        
        let rawURL = sessionURL.appendingPathComponent("lidar_test.raw")
        let jsonURL = sessionURL.appendingPathComponent("metadata.json")
        
        // Binary Write
        let binaryData = rawData.withUnsafeBytes { Data($0) }
        try? binaryData.write(to: rawURL)
        
        // Proper JSON Serialization (Fixes potential formatting errors)
        let metadata: [String: Any] = [
            "width": width,
            "height": height,
            "bitDepth": 16,
            "calibration": "1 unit = 25mm",
            "gps": [
                "lat": lastLocation?.coordinate.latitude ?? 0.0,
                "lon": lastLocation?.coordinate.longitude ?? 0.0,
                "alt": lastLocation?.altitude ?? 0.0
            ],
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted) {
            try? jsonData.write(to: jsonURL)
        }
        
        print("Test Session Complete: \(sessionURL.lastPathComponent)")
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
    }
}