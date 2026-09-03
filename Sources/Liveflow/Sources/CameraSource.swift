import Foundation
import AVFoundation
import CoreVideo
import CoreMedia

/// High performance camera video source using AVFoundation.
/// Output is native NV12 / CVPixelBuffer without CPU conversions.
public final class CameraSource: NSObject, VideoSource, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    public let id = UUID()
    public let name: String

    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.liveflow.camera", qos: .userInteractive)

    private let lock = NSLock()
    private var _latestFrame: VideoFrame?
    private var _isRunning = false
    private let deviceID: String?

    public var isRunning: Bool {
        lock.withLock { _isRunning }
    }

    public init(deviceID: String? = nil, name: String = "FaceTime HD Camera") {
        self.deviceID = deviceID
        self.name = name
        super.init()
    }

    public func start() async throws {
        let alreadyRunning = lock.withLock { () -> Bool in
            if _isRunning { return true }
            return false
        }
        guard !alreadyRunning else { return }

        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high

        let device: AVCaptureDevice?
        if let deviceID = self.deviceID {
            device = AVCaptureDevice(uniqueID: deviceID)
        } else {
            device = AVCaptureDevice.default(for: .video)
        }

        guard let camera = device else {
            captureSession.commitConfiguration()
            throw NSError(domain: "Liveflow", code: -2, userInfo: [NSLocalizedDescriptionKey: "No video camera device available"])
        }

        let input = try AVCaptureDeviceInput(device: camera)
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: queue)

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        captureSession.commitConfiguration()
        captureSession.startRunning()

        lock.withLock {
            _isRunning = true
        }
    }

    public func stop() async {
        let shouldStop = lock.withLock { () -> Bool in
            guard _isRunning else { return false }
            _isRunning = false
            return true
        }
        guard shouldStop else { return }

        captureSession.stopRunning()
    }

    public func currentFrame() -> VideoFrame? {
        lock.withLock { _latestFrame }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard sampleBuffer.isValid,
              let imageBuffer = sampleBuffer.imageBuffer else { return }

        let frame = VideoFrame(pixelBuffer: imageBuffer, timestamp: sampleBuffer.presentationTimeStamp)
        lock.withLock {
            _latestFrame = frame
        }
    }
}
