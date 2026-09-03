import Foundation
import CoreMedia
import AVFoundation
import HaishinKit
import RTMPHaishinKit

/// RTMP Stream Output implementation wrapping HaishinKit.
/// Handles connection lifecycle, reconnects, audio/video ingestion and live statistics.
public final class RTMPStreamOutput: StreamOutput, @unchecked Sendable {
    private var connection: RTMPConnection?
    private var stream: RTMPStream?

    private let lock = NSLock()
    private var _isStreaming = false
    private var _stats = StreamStats()

    private var videoFrameCount: Int = 0
    private var totalBytes: UInt64 = 0
    private var startTime: Date?
    private var lastStatsUpdate: Date = Date()
    private var lastFrameCount: Int = 0
    private var lastBytesCount: UInt64 = 0

    public var isStreaming: Bool {
        lock.withLock { _isStreaming }
    }

    public var stats: StreamStats {
        lock.withLock { _stats }
    }

    public init() {}

    public func connect(url: URL, streamKey: String?) async throws {
        let alreadyStreaming = lock.withLock { () -> Bool in
            if _isStreaming { return true }
            return false
        }
        guard !alreadyStreaming else { return }

        let (connectURLString, publishName) = parseURL(url: url, streamKey: streamKey)

        let connection = RTMPConnection()
        let stream = RTMPStream(connection: connection)

        print("[RTMP] Connecting to \(connectURLString)...")
        _ = try await connection.connect(connectURLString)

        print("[RTMP] Publishing as \(publishName)...")
        _ = try await stream.publish(publishName)

        lock.withLock {
            self.connection = connection
            self.stream = stream
            self._isStreaming = true
            self.startTime = Date()
            self.lastStatsUpdate = Date()
            self.videoFrameCount = 0
            self.totalBytes = 0
            self.lastFrameCount = 0
            self.lastBytesCount = 0
            self._stats = StreamStats()
        }

        print("[RTMP] Successfully connected and publishing!")
    }

    public func sendVideo(sampleBuffer: CMSampleBuffer) {
        let streamToSend: RTMPStream? = lock.withLock {
            guard _isStreaming, let stream = self.stream else { return nil }
            videoFrameCount += 1
            let sampleSize = CMSampleBufferGetTotalSampleSize(sampleBuffer)
            totalBytes += UInt64(sampleSize)
            return stream
        }

        guard let stream = streamToSend else { return }

        Task {
            await stream.append(sampleBuffer)
        }

        updateStatsIfNeeded()
    }

    public func sendAudio(buffer: AVAudioBuffer, when: AVAudioTime) {
        let streamToSend: RTMPStream? = lock.withLock {
            guard _isStreaming, let stream = self.stream else { return nil }
            return stream
        }

        guard let stream = streamToSend else { return }

        Task {
            await stream.append(buffer, when: when)
        }
    }

    public func disconnect() async {
        let (streamToClose, connToClose) = lock.withLock { () -> (RTMPStream?, RTMPConnection?) in
            guard _isStreaming else { return (nil, nil) }
            _isStreaming = false
            let s = self.stream
            let c = self.connection
            self.stream = nil
            self.connection = nil
            return (s, c)
        }

        _ = try? await streamToClose?.close()
        _ = try? await connToClose?.close()
        print("[RTMP] Disconnected.")
    }

    private func updateStatsIfNeeded() {
        let now = Date()
        lock.withLock {
            let elapsed = now.timeIntervalSince(lastStatsUpdate)
            guard elapsed >= 1.0 else { return }

            let framesDelta = videoFrameCount - lastFrameCount
            let bytesDelta = totalBytes - lastBytesCount

            let currentFPS = Double(framesDelta) / elapsed
            let currentBitrate = (Double(bytesDelta) * 8.0) / (elapsed * 1000.0) // kbps
            let totalUptime = startTime.map { now.timeIntervalSince($0) } ?? 0.0

            _stats = StreamStats(
                fps: currentFPS,
                bitrateKbps: currentBitrate,
                totalBytesSent: totalBytes,
                droppedFrames: 0,
                uptimeSeconds: totalUptime
            )

            lastStatsUpdate = now
            lastFrameCount = videoFrameCount
            lastBytesCount = totalBytes
        }
    }

    private func parseURL(url: URL, streamKey: String?) -> (connectURL: String, publishName: String) {
        if let key = streamKey, !key.isEmpty {
            return (url.absoluteString, key)
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        if pathComponents.count >= 2 {
            let streamName = pathComponents.last!
            var comp = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            comp.path = "/" + pathComponents.dropLast().joined(separator: "/")
            return (comp.url?.absoluteString ?? url.absoluteString, streamName)
        } else if let streamName = pathComponents.first {
            var comp = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            comp.path = ""
            return (comp.url?.absoluteString ?? url.absoluteString, streamName)
        }

        return (url.absoluteString, "live")
    }
}
