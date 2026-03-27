import AVFoundation
import UIKit

// MARK: - Video Output Delegate
extension HighSpeedCamera: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }

        // 1. Update Preview Texture
        self.latestPixelBuffer = pixelBuffer
        self.textureRegistry?.textureFrameAvailable(self.textureId)
        
        // 2. Histogram Analysis (Run every 4 frames to save CPU)
        self.frameCount += 1
        if self.frameCount % 30 == 0 { // Print once per second (at 120fps) to avoid flooding
            let metrics = calculateVisualMetrics(pixelBuffer)
            
            // --- DEBUG PRINT 1: Check Swift Math ---
            if let bright = metrics["brightness"], let edges = metrics["edges"] {
                let maxBright = bright.max() ?? 0
                let totalEdges = edges.reduce(0, +)
                print("SWIFT: Histogram Gen -> Max Bin: \(maxBright), Total Edge Energy: \(totalEdges)")
                
                // --- DEBUG PRINT 2: Check Bridge Status ---
                if SwiftBridge.sharedChannel == nil {
                    print("SWIFT ERROR: Method Channel is NIL! Data cannot reach Flutter.")
                } else {
                    SwiftBridge.sharedChannel?.invokeMethod("onHistogramUpdate", arguments: metrics)
                }
            }   
        }

        // 3. Recording Logic
        guard isRecording, let writer = self.writer, writer.status == .writing else { return }
        
        let ts = CMSampleBufferGetPresentationTimeStamp(buffer)
        
        if startTime == nil { 
            startTime = ts
            writer.startSession(atSourceTime: ts) 
        }

        if let input = self.writerInput, input.isReadyForMoreMediaData {
            input.append(buffer)
        }
    }

    // MARK: - Visual Analytics Engine
    private func calculateVisualMetrics(_ pixelBuffer: CVPixelBuffer) -> [String: [Int]] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return [:] }

        var brightnessHist = [Int](repeating: 0, count: 256)
        var edgeHist = [Int](repeating: 0, count: 256)

        let ptr = base.assumingMemoryBound(to: UInt8.self)

        // Stride of 8 for extreme efficiency on 4K frames
        for y in stride(from: 0, to: height, by: 8) {
            for x in stride(from: 0, to: width, by: 8) {
                let offset = y * bpr + x * 4
                
                // BGRA Format
                let b = Int(ptr[offset])
                let g = Int(ptr[offset + 1])
                let r = Int(ptr[offset + 2])

                // A. Luminance (Brightness) calculation
                let gray = (r * 299 + g * 587 + b * 114) / 1000
                brightnessHist[gray] += 1

                // B. Edge Detection (Horizontal Derivative)
                // Measures pixel-to-pixel contrast. High diff = Sharp edge.
                if x < width - 8 {
                    let nextOffset = offset + 32 // 8 pixels across
                    let nextB = Int(ptr[nextOffset])
                    let edgeIntensity = abs(b - nextB)
                    edgeHist[min(edgeIntensity, 255)] += 1
                }
            }
        }

        return [
            "brightness": brightnessHist,
            "edges": edgeHist
        ]
    }
}

extension HighSpeedCamera: AVCaptureDepthDataOutputDelegate {
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        guard captureDepthOnce else { return }
        captureDepthOnce = false
        
        let convertedDepth = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        saveDepthMap(convertedDepth.depthDataMap)
        
        depthSession?.stopRunning()
        DispatchQueue.main.async { self.depthCompletion?() }
    }

    internal func saveDepthMap(_ pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        // Add this at the beginning of the function (saveDepthMap or didOutput)
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
        let currentZoom = device.videoZoomFactor
        let zoomString = String(format: "%.1fx", currentZoom)

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer), 
            let folder = currentSessionFolderURL else { return }
        


        var rawData = [UInt16](repeating: 0, count: width * height)
        let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        for y in 0..<height {
            let row = base.advanced(by: y * bpr).assumingMemoryBound(to: Float32.self)
            for x in 0..<width {
                let depthInMeters = row[x]
                if depthInMeters.isNaN || depthInMeters < 0 {
                    rawData[y * width + x] = 0
                } else {
                    let mm = depthInMeters * 1000.0
                    rawData[y * width + x] = UInt16(clamping: Int(mm))
                }
            }
        }
        
        let rawURL = folder.appendingPathComponent("lidar_profile.raw")
        try? Data(buffer: UnsafeBufferPointer(start: rawData, count: rawData.count)).write(to: rawURL)
        
        let currentFPS = 1.0 / CMTimeGetSeconds(device.activeVideoMinFrameDuration)
        let exposureDuration = CMTimeGetSeconds(device.exposureDuration)
        let totalZoom = device.videoZoomFactor
        
        // 4. GPS Coordinates (from your locationManager property)
        let lat = lastLocation?.coordinate.latitude ?? 0.0
        let lon = lastLocation?.coordinate.longitude ?? 0.0
        let alt = lastLocation?.altitude ?? 0.0

        let meta: [String: Any] = [
            "experiment_details": [
                "name": self.experimentName,
                "description": self.experimentDesc
            ],
            "session_info": [
                "timestamp": Date().timeIntervalSince1970,
                "fps_actual": 1.0 / CMTimeGetSeconds(device.activeVideoMinFrameDuration),
                "exposure_seconds": CMTimeGetSeconds(device.exposureDuration),
                "iso": device.iso
            ],
            "optics": [
                "zoom_ratio_numeric": Double(currentZoom), // 1.2
                "zoom_display": zoomString,                // "1.2x"
                "lens_aperture": device.lensAperture,
                "base_zoom_factor": device.minAvailableVideoZoomFactor 
            ],
            "location": [
                "latitude": lastLocation?.coordinate.latitude ?? 0.0,
                "longitude": lastLocation?.coordinate.longitude ?? 0.0,
                "altitude_m": lastLocation?.altitude ?? 0.0
            ],
            "raw_format": [
                "width": width,
                "height": height,
                "unit": "UInt16_mm"
            ]
        ]

        if let data = try? JSONSerialization.data(withJSONObject: meta, options: .prettyPrinted),
            let folder = currentSessionFolderURL {
                try? data.write(to: folder.appendingPathComponent("metadata.json"))
                print("Successfully saved metadata for: \(self.experimentName)")
            }
    }
}