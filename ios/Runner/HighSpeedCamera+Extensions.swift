import AVFoundation
import UIKit

// MARK: - Video Output Delegate
extension HighSpeedCamera: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }
        
        // 1. Update Preview Texture
        self.latestPixelBuffer = pixelBuffer
        
        // PERFORMANCE FIX: Call registry directly on the camera queue. 
        // Flutter's textureRegistry is thread-safe. Jumping to Main at 120fps causes frame drops.
        self.textureRegistry?.textureFrameAvailable(self.textureId)

        // 2. High-Speed Recording Logic
        // Use a local reference to ensure the writer doesn't deallocate mid-frame
        guard isRecording, let writer = self.writer, writer.status == .writing else { return }
        
        let ts = CMSampleBufferGetPresentationTimeStamp(buffer)
        
        // Initialize Session on first frame
        if startTime == nil { 
            startTime = ts
            writer.startSession(atSourceTime: ts) 
        }
        
        // Append buffer if hardware is ready
        if let input = self.writerInput, input.isReadyForMoreMediaData {
            input.append(buffer)
        }
    }
}

// MARK: - Depth Data Delegate
extension HighSpeedCamera: AVCaptureDepthDataOutputDelegate {
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        guard captureDepthOnce else { return }
        captureDepthOnce = false
        
        // Ensure we use the 32-bit Float format for maximum precision for ANSYS
        let convertedDepth = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        saveDepthMap(convertedDepth.depthDataMap)
        
        depthSession?.stopRunning()
        DispatchQueue.main.async { self.depthCompletion?() }
    }

    internal func saveDepthMap(_ pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
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
                
                // CRITICAL FIX: Handle NaN or invalid depth values to prevent cast crashes
                if depthInMeters.isNaN || depthInMeters < 0 {
                    rawData[y * width + x] = 0
                } else {
                    // Convert meters to millimeters for your RAW profile
                    let mm = depthInMeters * 1000.0
                    rawData[y * width + x] = UInt16(clamping: Int(mm))
                }
            }
        }
        
        let rawURL = folder.appendingPathComponent("lidar_profile.raw")
        try? Data(buffer: UnsafeBufferPointer(start: rawData, count: rawData.count)).write(to: rawURL)
        
        // Metadata for post-processing alignment
        let meta: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "width": width,
            "height": height,
            "format": "UInt16_mm"
        ]
        if let data = try? JSONSerialization.data(withJSONObject: meta, options: .prettyPrinted) {
            try? data.write(to: folder.appendingPathComponent("metadata.json"))
        }
    }
}