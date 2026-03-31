import AVFoundation
import Photos
import UIKit
import CoreMotion
import CoreLocation
import Flutter

final class HighSpeedCamera: NSObject, FlutterTexture, CLLocationManagerDelegate {

    // MARK: - Core Properties
    internal var experimentName: String = ""
    internal var experimentDesc: String = ""
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
    internal var lastLocation: CLLocation?
    internal var currentSessionFolderURL: URL?
    private let mmPerPixelUnit: Float = 25.0
    private var distanceToIntensityLUT: [UInt16] = []
    // Flutter Texture Properties
    internal var textureRegistry: FlutterTextureRegistry?
    internal var textureId: Int64 = -1
    internal var latestPixelBuffer: CVPixelBuffer?
    // Define the channel property that was missing
    var channel: FlutterMethodChannel? 
    private var isLocked = false 
    private var lensPositionObserver: NSKeyValueObservation?
    private var activeVideoInput: AVCaptureDeviceInput?
    private var currentZoomFactor: CGFloat = 1.0
    private var didStartAccessing: Bool = false
    private var bookmarkDataKey = "synra_folder_bookmark"
    internal var audioRecorder: AVAudioRecorder?

    internal var customSaveRootURL: URL?
    internal var frameCount = 0
    internal var allowVibration: Bool = false

    func setSaveRoot(path: String) {
        let url = URL(fileURLWithPath: path)
        
        // 1. Try to start accessing
        let success = url.startAccessingSecurityScopedResource()
        
        if success {
            // 2. Create a PERSISTENT bookmark so we can remember this after restart
            do {
                let bookmarkData = try url.bookmarkData(options: .minimalBookmark, 
                                                    includingResourceValuesForKeys: nil, 
                                                    relativeTo: nil)
                UserDefaults.standard.set(bookmarkData, forKey: bookmarkDataKey)
                self.customSaveRootURL = url
                print("SYNRA: Persistent Bookmark Saved Successfully")
            } catch {
                print("SYNRA: Failed to create bookmark: \(error)")
            }
        }
    }

    func calculateHistograms(_ pixelBuffer: CVPixelBuffer) -> [String: [Int]] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return [:] }

        var brightnessHist = [Int](repeating: 0, count: 256)
        var edgeHist = [Int](repeating: 0, count: 256)

        let ptr = base.assumingMemoryBound(to: UInt8.self)

        // Sample every 4th pixel for performance
        for y in stride(from: 0, to: height, by: 4) {
            for x in stride(from: 0, to: width, by: 4) {
                let offset = y * bpr + x * 4
                let b = Int(ptr[offset])
                let g = Int(ptr[offset + 1])
                let r = Int(ptr[offset + 2])

                // 1. Brightness (Luminance)
                let gray = (r * 299 + g * 587 + b * 114) / 1000
                brightnessHist[gray] += 1

                // 2. Simple Edge Detection (Sobel-lite)
                // Compare current pixel to the one next to it
                if x < width - 4 {
                    let nextB = Int(ptr[offset + 4])
                    let diff = abs(b - nextB)
                    edgeHist[min(diff, 255)] += 1
                }
            }
        }

        return ["brightness": brightnessHist, "edges": edgeHist]
    }

    // 3. Add this new function to call on app boot
    func restoreSavedBookmark() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkDataKey) else { return }
        
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: data, 
                            options: .withoutUI, 
                            relativeTo: nil, 
                            bookmarkDataIsStale: &isStale)
            
            if url.startAccessingSecurityScopedResource() {
                self.customSaveRootURL = url
                print("SYNRA: Restored Security Access to: \(url.path)")
            }
        } catch {
            print("SYNRA: Failed to restore bookmark: \(error)")
        }
    }

    func setLock(_ locked: Bool) {
        self.isLocked = locked
    }

    override init() {
        super.init()
        setupLUT()
        setupLocation()
    }

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
    private func startAudioRecording() {
        guard let folder = currentSessionFolderURL else { return }
        let audioURL = folder.appendingPathComponent("audio_log.m4a") // iOS prefers .m4a (AAC), standard for experiments
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .videoRecording, options: .defaultToSpeaker)
            try session.setActive(true)
            
            audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
            audioRecorder?.record()
            print("SYNRA: Audio recording started at \(audioURL.path)")
        } catch {
            print("SYNRA: Audio setup failed: \(error)")
        }
    }

    func startRecording(fps: Int, name: String, description: String) {
        self.experimentName = name.isEmpty ? "Unnamed_Session" : name
        self.experimentDesc = description

        self.createSessionFolder()
        startAudioRecording()
        queue.async {

            self.configureSession(fps: fps)
            // 2. Start the sensor
            if !self.session.isRunning { 
                self.session.startRunning() 
            }

            self.configureWriter(fps: fps)

            self.startTime = nil
            self.isRecording = true
            self.startIMU()

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

// Added completion block to pass the file path back to Flutter
    func stopRecording(completion: ((String?) -> Void)? = nil) {

        if !isRecording && writer == nil {
            self.currentSessionFolderURL = nil 
            completion?(nil)
            return
        }
        // 1. Immediate state change to stop the frame buffer
        isRecording = false
        motionManager.stopDeviceMotionUpdates()
        altimeter.stopRelativeAltitudeUpdates()

        audioRecorder?.stop()
        audioRecorder = nil
        
        // Capture the URL before we nil out the writer
        let outputURL = self.writer?.outputURL

        queue.async {
            // 2. CRITICAL GUARD: Only finish if the writer is actually in 'writing' status (1)
            if let writer = self.writer, writer.status == .writing {
                self.writerInput?.markAsFinished()
                writer.finishWriting { [weak self] in
                    guard let self = self else { return }
                    if let url = outputURL {
                        self.saveToLibrary(url: url)
                        self.saveIMUDataSidecar(videoURL: url)
                    }
                    self.cleanupAfterSession()
                    DispatchQueue.main.async { completion?(outputURL?.path) }
                }
            } else {
                // 3. If writer is already finished (status 2) or failed, just cleanup
                self.cleanupAfterSession()
                DispatchQueue.main.async { completion?(nil) }
            }
            }
        }
    
    
    // Helper to keep code clean
    private func cleanupAfterSession() {
        self.writer = nil
        self.writerInput = nil
        self.currentSessionFolderURL = nil 
        self.experimentName = ""
        self.experimentDesc = ""
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

            if self.currentSessionFolderURL != nil {
                print("Reusing existing session folder: \(self.currentSessionFolderURL!.lastPathComponent)")
                return
            }

            let baseDirectory: URL
            if let customRoot = self.customSaveRootURL {
                baseDirectory = customRoot
            } else {
                baseDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let folderName = "Session_\(formatter.string(from: Date()))"
            let folderURL = baseDirectory.appendingPathComponent(folderName)
            
            do {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
                self.currentSessionFolderURL = folderURL
                print("Created NEW session folder at: \(folderURL.path)")
            } catch {
                print("Error creating folder: \(error)")
                
                // CRITICAL FALLBACK: If custom path (like an SSD) fails, use local documents
                let fallbackRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let fallbackURL = fallbackRoot.appendingPathComponent(folderName)
                try? FileManager.default.createDirectory(at: fallbackURL, withIntermediateDirectories: true)
                self.currentSessionFolderURL = fallbackURL
            }
        }

    func saveVoiceMemo(tempPath: String) {
        self.createSessionFolder() // Ensure folder exists
        guard let folder = currentSessionFolderURL else { return }
        let destinationURL = folder.appendingPathComponent("memo.mp3")
        let sourceURL = URL(fileURLWithPath: tempPath)
        
        try? FileManager.default.removeItem(at: destinationURL) // Remove if exists
        try? FileManager.default.moveItem(at: sourceURL, to: destinationURL)
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
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
         self.lastLocation = locations.last 
         }
    
    func captureLidarProfile(completion: @escaping () -> Void) {
        // 1. Prepare folder and state before jumping to background thread
        self.createSessionFolder()
        self.depthCompletion = completion
        self.captureDepthOnce = true
        
        queue.async {
            // 2. RELEASE HARDWARE: High-speed video and LiDAR cannot share the ISP.
            // We MUST stop the main preview session to allow the LiDAR hardware to initialize.
            if self.session.isRunning {
                print("SWIFT: Pausing main preview for LiDAR capture...")
                self.session.stopRunning()
                // Tiny sleep to allow the hardware clock to settle
                Thread.sleep(forTimeInterval: 0.1) 
            }

            guard let device = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) else {
                print("SWIFT: LiDAR Hardware missing or unsupported")
                DispatchQueue.main.async { completion() }
                return 
            }

            let lSession = AVCaptureSession()
            lSession.beginConfiguration()
            
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if lSession.canAddInput(input) { lSession.addInput(input) }
                
                self.depthOutput.setDelegate(self, callbackQueue: self.queue)
                if lSession.canAddOutput(self.depthOutput) { lSession.addOutput(self.depthOutput) }
                
                lSession.commitConfiguration()
                self.depthSession = lSession
                
                print("SWIFT: Starting LiDAR Session...")
                lSession.startRunning()

                // 3. SAFETY TIMEOUT: If no depth frame is received in 3.5s, unblock Flutter.
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
                    guard let self = self else { return }
                    if self.depthCompletion != nil {
                        print("SWIFT: LiDAR Capture Timeout - Reverting to Preview")
                        self.depthCompletion?()
                        self.depthCompletion = nil
                        
                        self.queue.async {
                            self.depthSession?.stopRunning()
                            self.depthSession = nil
                            self.session.startRunning() // Resume preview so UI isn't dead
                        }
                    }
                }
            } catch {
                print("SWIFT: LiDAR Setup Failed: \(error)")
                self.session.startRunning()
                DispatchQueue.main.async { completion() }
            }
        }
        print("1.5 - Capture Logic Initialized")
    }
}
