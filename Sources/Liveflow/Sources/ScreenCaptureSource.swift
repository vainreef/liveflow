import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo

/// High performance screen capture source using Apple's ScreenCaptureKit.
/// Output is zero-copy IOSurface-backed CVPixelBuffer.
public final class ScreenCaptureSource: NSObject, VideoSource, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    public let id = UUID()
    public let name: String

    private var stream: SCStream?
    private let queue = DispatchQueue(label: "com.liveflow.screencapture", qos: .userInteractive)
    private let lock = NSLock()
    private var _latestFrame: VideoFrame?
    private var _isRunning = false
    private let targetDisplayIndex: Int

    public var isRunning: Bool {
        lock.withLock { _isRunning }
    }

    public init(displayIndex: Int = 0, name: String = "Main Display") {
        self.targetDisplayIndex = displayIndex
        self.name = name
        super.init()
    }

    public func start() async throws {
        let alreadyRunning = lock.withLock { () -> Bool in
            if _isRunning { return true }
            return false
        }
        guard !alreadyRunning else { return }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard !content.displays.isEmpty else {
            throw NSError(domain: "Liveflow", code: -1, userInfo: [NSLocalizedDescriptionKey: "No displays found for ScreenCaptureKit"])
        }

        let display = (targetDisplayIndex < content.displays.count) ? content.displays[targetDisplayIndex] : content.displays[0]
        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 5
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()

        self.stream = stream
        lock.withLock {
            _isRunning = true
        }
    }

    public func stop() async {
        let streamToStop = lock.withLock { () -> SCStream? in
            guard _isRunning else { return nil }
            _isRunning = false
            let s = self.stream
            self.stream = nil
            return s
        }

        try? await streamToStop?.stopCapture()
    }

    public func currentFrame() -> VideoFrame? {
        lock.withLock { _latestFrame }
    }

    // MARK: - SCStreamOutput
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              sampleBuffer.isValid,
              let imageBuffer = sampleBuffer.imageBuffer else { return }

        let frame = VideoFrame(pixelBuffer: imageBuffer, timestamp: sampleBuffer.presentationTimeStamp)
        lock.withLock {
            _latestFrame = frame
        }
    }

    // MARK: - SCStreamDelegate
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.withLock {
            _isRunning = false
        }
        print("ScreenCaptureKit stream stopped with error: \(error)")
    }
}
