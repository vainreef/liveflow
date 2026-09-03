import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import CoreGraphics

public struct DisplayItem: Identifiable, @unchecked Sendable {
    public let id: CGDirectDisplayID
    public let name: String
    public let width: Int
    public let height: Int
    public let scDisplay: SCDisplay

    public init(scDisplay: SCDisplay, index: Int) {
        self.id = scDisplay.displayID
        self.width = scDisplay.width
        self.height = scDisplay.height
        self.scDisplay = scDisplay
        self.name = "Display \(index + 1) (\(scDisplay.width)×\(scDisplay.height))"
    }
}

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
    private let targetDisplayID: CGDirectDisplayID?
    private let targetDisplay: SCDisplay?

    public var isRunning: Bool {
        lock.withLock { _isRunning }
    }

    public init(display: SCDisplay? = nil, displayID: CGDirectDisplayID? = nil, name: String? = nil) {
        self.targetDisplay = display
        self.targetDisplayID = displayID ?? display?.displayID
        if let name = name {
            self.name = name
        } else if let display = display {
            self.name = "Display (\(display.width)×\(display.height))"
        } else {
            self.name = "Screen Capture"
        }
        super.init()
    }

    /// Queries all available displays currently connected to the Mac
    public static func getAvailableDisplays() async throws -> [DisplayItem] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return content.displays.enumerated().map { idx, display in
            DisplayItem(scDisplay: display, index: idx)
        }
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

        let selectedDisplay: SCDisplay
        if let targetID = targetDisplayID, let match = content.displays.first(where: { $0.displayID == targetID }) {
            selectedDisplay = match
        } else if let target = targetDisplay {
            selectedDisplay = target
        } else {
            selectedDisplay = content.displays[0]
        }

        let filter = SCContentFilter(display: selectedDisplay, excludingWindows: [])

        let config = SCStreamConfiguration()
        config.width = selectedDisplay.width
        config.height = selectedDisplay.height
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
        print("[ScreenCaptureKit] Started capturing display: \(selectedDisplay.displayID) (\(selectedDisplay.width)x\(selectedDisplay.height))")
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
