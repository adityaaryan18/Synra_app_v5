import AVFoundation
import Photos
import UIKit
import CoreMotion
import CoreLocation
import Flutter

final class HighSpeedCamera: NSObject, FlutterTexture, CLLocationManagerDelegate {

    // MARK: - Core Properties
    private let session = AVCaptureSession()
    internal let queue = DispatchQueue(label: "hs.camera.queue", qos: .userInteractive)

    private let altimeter = CMAltimeter()
    private var latestPressure: Double = 1013.25

    internal var videoOutput: AVCaptureVideoDataOutput!
    internal var writer: AVAssetWriter?
    internal var writerInput: AVAssetWriterInput?

    internal var isRecording = false
    internal var startTime: CMTime?

    private let motionManager = CMMotionManager()

    private var imuData: [(CMTime, CMAcceleration, CMRotationRate, Double)] = []

    internal var depthSession: AVCaptureSession?
    internal let depthOutput = AVCaptureDepthDataOutput()
    internal var captureDepthOnce = false
    internal var depthCompletion: (() -> Void)?
    
    private let locationManager = CLLocationManager()
    private var lastLocation: CLLocation?
    internal var currentSessionFolderURL: URL?
    
    private let mmPerPixelUnit: Float = 25.0
    private var distanceToIntensityLUT: [UInt16] = []
    
    // MARK: - Flutter Texture Properties
    internal var textureRegistry: FlutterTextureRegistry?
    internal var textureId: Int64 = -1
    internal var latestPixelBuffer: CVPixelBuffer?
    
    // FIX: Define the channel property that was missing
    var channel: FlutterMethodChannel? 
    
    private var isLocked = false 
    private var lensPositionObserver: NSKeyValueObservation?
    private var activeVideoInput: AVCaptureDeviceInput?
    private var currentZoomFactor: CGFloat = 1.0

    func setLock(_ locked: Bool) {
        self.isLocked = locked
    }

    override init() {
        super.init()
        setupLUT()
        setupLocation()
    }

    // MARK: - Flutter Texture Setup
    
    func setupPreview(registry: FlutterTextureRegistry) -> Int64 {
        self.textureRegistry = registry
        self.textureId = registry.register(self)
        
        queue.async {
            self.configureSession(fps: 60)
            self.session.startRunning()
        }
        return self.textureId
    }

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let buffer = latestPixelBuffer else { return nil }
        return Unmanaged.passRetained(buffer)
    }

    // MARK: - Manual Hardware Controls

    func updateISO(_ iso: Float) {
        if isLocked { return }
        queue.async {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
            try? device.lockForConfiguration()
            let clampedISO = max(device.activeFormat.minISO, min(iso, device.activeFormat.maxISO))
            device.setExposureModeCustom(duration: device.exposureDuration, iso: clampedISO, completionHandler: nil)
            device.unlockForConfiguration()
        }
    }

    func updatePressure(_ pressure: Double) {
            // We jump onto the camera queue to ensure thread-safety 
            // when updating the value used by the IMU CSV logger
            queue.async {
                self.latestPressure = pressure
            }
        }

    func updateShutterSpeed(_ shutterString: String) {
        queue.async {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
            let components = shutterString.components(separatedBy: "/")
            guard components.count == 2, let den = Double(components[1]) else { return }
            let seconds = 1.0 / den
            let duration = CMTimeMakeWithSeconds(seconds, preferredTimescale: 1000000)
            
            try? device.lockForConfiguration()
            let maxDuration = CMTime(value: 1, timescale: 120)
            let safeDuration = duration.seconds > maxDuration.seconds ? maxDuration : duration
            device.setExposureModeCustom(duration: safeDuration, iso: device.iso, completionHandler: nil)
            device.unlockForConfiguration()
        }
    }

    func updateFocus(_ lensPosition: Float) {
        if isLocked { return }
        queue.async {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
            try? device.lockForConfiguration()
            device.setFocusModeLocked(lensPosition: lensPosition, completionHandler: nil)
            device.unlockForConfiguration()
        }
    }

    func updateWB(_ temperature: Float) {
        if isLocked { return }
        queue.async {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
            try? device.lockForConfiguration()
            let gains = device.deviceWhiteBalanceGains(for: AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: temperature, tint: 0))
            device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
            device.unlockForConfiguration()
        }
    }

    func updateZoom(_ factor: CGFloat) {
        if isLocked { return }
        // SAVE THE FACTOR LOCALLY SO THE RECORDING LOGIC CAN SEE IT
        self.currentZoomFactor = factor 
        
        queue.async {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
            do {
                try device.lockForConfiguration()
                let clampedFactor = max(1.0, min(factor, device.activeFormat.videoMaxZoomFactor))
                device.videoZoomFactor = clampedFactor 
                device.unlockForConfiguration()
            } catch { print("Zoom Error: \(error)") }
        }   
    }

    // MARK: - Session Management

// MARK: - Session Management

    func startRecording(fps: Int) {
        self.createSessionFolder()
        queue.async {
            // 1. Force a clean 120fps format configuration
            self.configureSession(fps: fps)
            
            // 2. Start the sensor
            if !self.session.isRunning { 
                self.session.startRunning() 
            }

            // 3. Initialize the Writer (Calls writer?.startWriting() internally)
            self.configureWriter(fps: fps)
            
            // 4. Update state and start sensors
            self.startTime = nil
            self.isRecording = true
            self.startIMU()
            
            // 5. THE ZOOM & FPS PERSISTENCE FIX:
            // We apply the settings at 150ms AND 350ms. 
            // This catches the hardware after the initial ProRes encoder reset.
            let enforcementDelays = [0.15, 0.35]
            
            for delay in enforcementDelays {
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self = self, 
                        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) 
                    else { return }
                    
                    do {
                        try device.lockForConfiguration()
                        
                        // A. Check if we need to restore the 4K/120fps format
                        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
                        let ranges = device.activeFormat.videoSupportedFrameRateRanges
                        let currentSupports120 = ranges.contains { $0.maxFrameRate >= Double(fps) }

                        if dims.width != 3840 || !currentSupports120 {
                            if let bestFormat = device.formats.first(where: { f in
                                let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
                                let r = f.videoSupportedFrameRateRanges
                                return d.width == 3840 && d.height == 2160 && r.contains { $0.maxFrameRate >= Double(fps) }
                            }) {
                                device.activeFormat = bestFormat
                            }
                        }
                        
                        // B. Re-enforce the frame rate duration
                        let supportedRanges = device.activeFormat.videoSupportedFrameRateRanges
                        if let range = supportedRanges.first(where: { $0.maxFrameRate >= Double(fps) }) {
                            device.activeVideoMinFrameDuration = range.minFrameDuration
                            device.activeVideoMaxFrameDuration = range.minFrameDuration
                        }
                        
                        // C. THE ZOOM FIX: Re-enforce the factor stored in the class
                        let factor = max(1.0, min(self.currentZoomFactor, device.activeFormat.videoMaxZoomFactor))
                        device.videoZoomFactor = factor
                        
                        device.unlockForConfiguration()
                        print("zoom Verification at \(delay)s: \(factor)x zoom at \(fps)fps")
                    } catch {
                        print("Hardware enforcement failed: \(error)")
                    }
                }
            }
        }
    }
    func configureSession(fps: Int) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
        
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        
        // Find 4K 120fps format
        let bestFormat = device.formats.first { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dims.width == 3840 && dims.height == 2160 && 
                   format.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= Double(fps) })
        }
        
        if let selectedFormat = bestFormat {
            do {
                try device.lockForConfiguration()
                device.activeFormat = selectedFormat
                let duration = CMTime(value: 1, timescale: Int32(fps))
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
                device.unlockForConfiguration()
            } catch { print("Format lock failed") }
        }

        if let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }
        
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        
        if session.canAddOutput(output) {
            session.addOutput(output)
            self.videoOutput = output
            
            if let connection = output.connection(with: .video) {
                // Must be OFF for 120fps + Zoom stability
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .off 
                }
                
                if connection.isVideoOrientationSupported {
                    let orientation = DispatchQueue.main.sync { UIDevice.current.orientation }
                    switch orientation {
                    case .landscapeLeft: connection.videoOrientation = .landscapeRight
                    case .landscapeRight: connection.videoOrientation = .landscapeLeft
                    case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
                    default: connection.videoOrientation = .portrait
                    }
                }
            }
        }
        session.commitConfiguration()
    }

    func stopRecording() {
        isRecording = false
        motionManager.stopDeviceMotionUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        queue.async {
            self.writerInput?.markAsFinished()
            self.writer?.finishWriting { [weak self] in
                guard let self = self, let url = self.writer?.outputURL else { return }
                self.saveToLibrary(url: url)
                self.saveIMUDataSidecar(videoURL: url)
                self.writer = nil
                self.writerInput = nil
            }
        }
    }
    


    func configureWriter(fps: Int) {
        guard let folder = currentSessionFolderURL else { return }
        let url = folder.appendingPathComponent("video_4K_120_ProRes.mov")
        
        writer = try? AVAssetWriter(outputURL: url, fileType: .mov)

        let isPortrait = UIDevice.current.orientation.isPortrait || UIDevice.current.orientation == .unknown
        let videoWidth = isPortrait ? 2160 : 3840
        let videoHeight = isPortrait ? 3840 : 2160

        let compressionSettings: [String: Any] = [
            AVVideoAverageBitRateKey: 200_000_000, 
            AVVideoExpectedSourceFrameRateKey: fps 
        ]

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.proRes422,
            AVVideoWidthKey: videoWidth,
            AVVideoHeightKey: videoHeight,
            AVVideoCompressionPropertiesKey: compressionSettings
        ]

        writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        writerInput?.expectsMediaDataInRealTime = true
        
        if isPortrait {
            writerInput?.transform = CGAffineTransform(rotationAngle: .pi / 2)
        } else if UIDevice.current.orientation == .landscapeRight {
            writerInput?.transform = CGAffineTransform(rotationAngle: .pi)
        }

        if let input = writerInput, writer!.canAdd(input) {
            writer!.add(input)
        }
        
        writer?.startWriting()
        startTime = nil
    }
    
    private func sendFocusUpdateToFlutter(_ position: Float) {
        if let ch = self.channel {
            ch.invokeMethod("onFocusChanged", arguments: position)
        } else {
            SwiftBridge.sharedChannel?.invokeMethod("onFocusChanged", arguments: position)
        }
    }

    // MARK: - Helpers
    
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

    internal func createSessionFolder() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let folderName = "Session_\(formatter.string(from: Date()))"
        let folderURL = docs.appendingPathComponent(folderName)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        self.currentSessionFolderURL = folderURL
    }

    private func startIMU() {
        imuData.removeAll()
        
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
                guard let self = self, let data = data else { return }
                self.latestPressure = data.pressure.doubleValue * 10.0
            }
        }

        motionManager.deviceMotionUpdateInterval = 1.0 / 240.0
        if motionManager.isDeviceMotionAvailable {
            motionManager.startDeviceMotionUpdates(to: .main) { motion, _ in
                guard let motion = motion else { return }
                self.queue.async {
                    self.imuData.append((
                        CMClockGetTime(CMClockGetHostTimeClock()), 
                        motion.userAcceleration, 
                        motion.rotationRate, 
                        self.latestPressure
                    ))
                }
            }
        }
    }

    internal func saveIMUDataSidecar(videoURL: URL) {
        guard let folder = currentSessionFolderURL else { return }
        let imuURL = folder.appendingPathComponent("imu_data.csv")
        
        var csv = "timestamp,ax,ay,az,gx,gy,gz,pressure_hpa\n"
        
        for entry in imuData {
            let ts = CMTimeGetSeconds(entry.0)
            csv += "\(ts),\(entry.1.x),\(entry.1.y),\(entry.1.z),\(entry.2.x),\(entry.2.y),\(entry.2.z),\(entry.3)\n"
        }
        try? csv.write(to: imuURL, atomically: true, encoding: .utf8)
    }
    
    internal func saveToLibrary(url: URL) {
        PHPhotoLibrary.shared().performChanges({ PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) })
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { lastLocation = locations.last }
    
    func captureLidarProfile(completion: @escaping () -> Void) {
        self.createSessionFolder()
        queue.async {
            guard let device = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) else { completion(); return }
            let session = AVCaptureSession()
            session.beginConfiguration()
            if let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) { session.addInput(input) }
            self.depthOutput.setDelegate(self, callbackQueue: self.queue)
            if session.canAddOutput(self.depthOutput) { session.addOutput(self.depthOutput) }
            session.commitConfiguration()
            self.depthSession = session
            self.depthCompletion = completion
            self.captureDepthOnce = true
            session.startRunning()
        }
    }
}