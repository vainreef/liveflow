import Foundation
import CoreVideo
import CoreMedia
import QuartzCore
import CoreGraphics
import CoreText

/// Generates an animated test pattern (color bars, moving box, timestamp)
/// directly into IOSurface-backed CVPixelBuffers at 60fps.
/// Ensures immediate out-of-the-box streamability without permissions needed.
public final class TestPatternSource: VideoSource, @unchecked Sendable {
    public let id = UUID()
    public let name = "Test Pattern"

    private let width: Int
    private let height: Int
    private let fps: Int

    private var pixelBufferPool: CVPixelBufferPool?
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.livestreamer.testpattern", qos: .userInteractive)

    private let lock = NSLock()
    private var _latestFrame: VideoFrame?
    private var _isRunning = false
    private var frameIndex: Int = 0

    public var isRunning: Bool {
        lock.withLock { _isRunning }
    }

    public init(width: Int = 1920, height: Int = 1080, fps: Int = 60) {
        self.width = width
        self.height = height
        self.fps = fps
        setupPool()
    }

    private func setupPool() {
        let poolAttributes: [CFString: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey: 3
        ]
        let bufferAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey: true
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes as CFDictionary, bufferAttributes as CFDictionary, &pixelBufferPool)
    }

    public func start() async throws {
        let alreadyRunning = lock.withLock { () -> Bool in
            if _isRunning { return true }
            _isRunning = true
            return false
        }
        guard !alreadyRunning else { return }

        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        let interval = 1.0 / Double(fps)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            self?.generateNextFrame()
        }
        self.timer = timer
        timer.resume()
    }

    public func stop() async {
        lock.withLock {
            _isRunning = false
            timer?.cancel()
            timer = nil
        }
    }

    public func currentFrame() -> VideoFrame? {
        lock.withLock { _latestFrame }
    }

    private func generateNextFrame() {
        guard let pool = pixelBufferPool else { return }
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }

        frameIndex += 1
        let t = Double(frameIndex) / Double(fps)

        // 1. Color Bars
        let barColors: [CGColor] = [
            CGColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1.0), // Light Gray
            CGColor(red: 0.85, green: 0.85, blue: 0.0,  alpha: 1.0), // Yellow
            CGColor(red: 0.0,  green: 0.85, blue: 0.85, alpha: 1.0), // Cyan
            CGColor(red: 0.0,  green: 0.85, blue: 0.0,  alpha: 1.0), // Green
            CGColor(red: 0.85, green: 0.0,  blue: 0.85, alpha: 1.0), // Magenta
            CGColor(red: 0.85, green: 0.0,  blue: 0.0,  alpha: 1.0), // Red
            CGColor(red: 0.0,  green: 0.0,  blue: 0.85, alpha: 1.0)  // Blue
        ]
        let barWidth = CGFloat(width) / CGFloat(barColors.count)
        for (i, color) in barColors.enumerated() {
            context.setFillColor(color)
            context.fill(CGRect(x: CGFloat(i) * barWidth, y: 0, width: barWidth, height: CGFloat(height)))
        }

        // 2. Darker bottom third
        context.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 0.92))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height) / 3.0))

        // 3. Moving bouncing badge
        let boxWidth: CGFloat = 300
        let boxHeight: CGFloat = 80
        let bounceRange = CGFloat(width) - boxWidth - 40
        let normalizedPos = (sin(t * 2.0) + 1.0) / 2.0
        let boxX = 20 + normalizedPos * bounceRange
        let boxY = CGFloat(height) * 0.12

        context.setFillColor(CGColor(red: 0.1, green: 0.6, blue: 1.0, alpha: 0.95))
        let path = CGPath(roundedRect: CGRect(x: boxX, y: boxY, width: boxWidth, height: boxHeight), cornerWidth: 14, cornerHeight: 14, transform: nil)
        context.addPath(path)
        context.fillPath()

        drawText(in: context, text: "LIVESTREAMER LIVE", x: boxX + 22, y: boxY + 28, fontSize: 28, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))

        // 4. Top info header banner
        context.setFillColor(CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.8))
        context.fill(CGRect(x: 0, y: CGFloat(height) - 90, width: CGFloat(width), height: 90))

        drawText(in: context, text: "Apple Silicon Native Live Streaming Engine", x: 30, y: CGFloat(height) - 55, fontSize: 32, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))

        let timeStr = String(format: "Time: %.2fs | Frame: %d | 60 FPS", t, frameIndex)
        drawText(in: context, text: timeStr, x: CGFloat(width) - 520, y: CGFloat(height) - 55, fontSize: 26, color: CGColor(red: 0.7, green: 0.9, blue: 1.0, alpha: 1))

        let pts = CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(fps))
        let frame = VideoFrame(pixelBuffer: buffer, timestamp: pts)

        lock.withLock {
            _latestFrame = frame
        }
    }

    private func drawText(in context: CGContext, text: String, x: CGFloat, y: CGFloat, fontSize: CGFloat, color: CGColor) {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
    }
}
