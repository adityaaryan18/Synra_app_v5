import AVFoundation
import Flutter
import UIKit

class ContextCamera: NSObject, FlutterTexture {

    private let session = AVCaptureMultiCamSession()
    
    // Separate queues (IMPORTANT)
    private let sessionQueue = DispatchQueue(label: "synra.context.session")
    private let outputQueue = DispatchQueue(label: "synra.context.output")
    
    private var textureRegistry: FlutterTextureRegistry?
    private var textureId: Int64 = -1
    
    private var latestBuffer: CVPixelBuffer?

    // MARK: - Flutter Texture Pull
    public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        guard let buffer = latestBuffer else { return nil }
        return Unmanaged.passRetained(buffer)
    }

    // MARK: - Setup
    func setupContextPreview(registry: FlutterTextureRegistry) -> Int64 {
        self.textureRegistry = registry
        self.textureId = registry.register(self)

        sessionQueue.async {
            self.configureContextSession()
            
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }

        return self.textureId
    }

    // MARK: - Configuration
    private func configureContextSession() {
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            print("❌ MultiCam not supported")
            return
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.automaticallyConfiguresApplicationAudioSession = false

        // Ultra-wide camera
        guard let device = AVCaptureDevice.default(.builtInUltraWideCamera,
                                                   for: .video,
                                                   position: .back) else {
            print("❌ No ultra-wide camera")
            return
        }

        // Low-res format (MultiCam safe)
        let lowResFormat = device.formats.first { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dims.width <= 1280 && format.isMultiCamSupported
        }

        if let format = lowResFormat {
            do {
                try device.lockForConfiguration()
                device.activeFormat = format
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                device.unlockForConfiguration()
            } catch {
                print("❌ Format error: \(error)")
                return
            }
        }

        // Input
        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            print("❌ Cannot add input")
            return
        }
        session.addInputWithNoConnections(input)

        // Output
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: outputQueue)

        guard session.canAddOutput(output) else {
            print("❌ Cannot add output")
            return
        }
        session.addOutputWithNoConnections(output)

        // ✅ FIXED: Correct port selection (NO device type filter)
        guard let port = input.ports.first(where: {
            $0.mediaType == .video
        }) else {
            print("❌ No video port")
            return
        }

        let connection = AVCaptureConnection(inputPorts: [port], output: output)

        if session.canAddConnection(connection) {
            session.addConnection(connection)

            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }

            connection.isVideoMirrored = false
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isEnabled = true

            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .off
            }
        } else {
            print("❌ Cannot add connection")
            return
        }
    }
}

// MARK: - Output Delegate
extension ContextCamera: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        print("frame received") // DEBUG

        guard let srcBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let width = CVPixelBufferGetWidth(srcBuffer)
        let height = CVPixelBufferGetHeight(srcBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(srcBuffer)

        var newBuffer: CVPixelBuffer?

        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary

        CVPixelBufferCreate(kCFAllocatorDefault,
                            width,
                            height,
                            pixelFormat,
                            attrs,
                            &newBuffer)

        guard let dstBuffer = newBuffer else { return }

        // Copy memory (FIXES FREEZE)
        CVPixelBufferLockBaseAddress(srcBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(dstBuffer, [])

        if let srcBase = CVPixelBufferGetBaseAddress(srcBuffer),
           let dstBase = CVPixelBufferGetBaseAddress(dstBuffer) {

            let bytesPerRow = CVPixelBufferGetBytesPerRow(srcBuffer)
            memcpy(dstBase, srcBase, bytesPerRow * height)
        }

        CVPixelBufferUnlockBaseAddress(dstBuffer, [])
        CVPixelBufferUnlockBaseAddress(srcBuffer, .readOnly)

        // Store safely
        objc_sync_enter(self)
        self.latestBuffer = dstBuffer
        objc_sync_exit(self)

        // Notify Flutter
        textureRegistry?.textureFrameAvailable(textureId)
    }
}