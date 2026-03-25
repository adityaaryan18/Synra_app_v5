import AVFoundation
import UIKit

// MARK: - Video Output Delegate
extension HighSpeedCamera: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }

        self.latestPixelBuffer = pixelBuffer
        self.textureRegistry?.textureFrameAvailable(self.textureId)
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