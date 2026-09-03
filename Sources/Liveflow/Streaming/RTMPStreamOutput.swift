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

    private enum StreamItem: Sendable {
        case video(CMSampleBuffer)
        case audio(AVAudioBuffer, AVAudioTime)
    }

    private var streamContinuation: AsyncStream<StreamItem>.Continuation?
    private var streamConsumerTask: Task<Void, Never>?

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

        let (streamItems, continuation) = AsyncStream.makeStream(
            of: StreamItem.self,
            bufferingPolicy: .bufferingNewest(8)
        )
        let consumer = Task { [weak stream] in
            for await item in streamItems {
                guard let stream = stream else { break }
                switch item {
                case .video(let sampleBuffer):
                    await stream.append(sampleBuffer)
                case .audio(let buffer, let when):
                    await stream.append(buffer, when: when)
                }
            }
        }

        lock.withLock {
            self.connection = connection
            self.stream = stream
            self.streamContinuation = continuation
            self.streamConsumerTask = consumer
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
        let continuation: AsyncStream<StreamItem>.Continuation? = lock.withLock {
            guard _isStreaming, stream != nil else { return nil }
            videoFrameCount += 1
            let sampleSize = CMSampleBufferGetTotalSampleSize(sampleBuffer)
            totalBytes += UInt64(sampleSize)
            return streamContinuation
        }

        continuation?.yield(.video(sampleBuffer))
        updateStatsIfNeeded()
    }

    public func sendAudio(buffer: AVAudioBuffer, when: AVAudioTime) {
        let continuation: AsyncStream<StreamItem>.Continuation? = lock.withLock {
            guard _isStreaming, stream != nil else { return nil }
            return streamContinuation
        }

        continuation?.yield(.audio(buffer, when))
    }

    public func disconnect() async {
        let (streamToClose, connToClose, continuation, consumer) = lock.withLock {
            () -> (RTMPStream?, RTMPConnection?, AsyncStream<StreamItem>.Continuation?, Task<Void, Never>?) in
            guard _isStreaming else { return (nil, nil, nil, nil) }
            _isStreaming = false
            let s = self.stream
            let c = self.connection
            let cont = self.streamContinuation
            let task = self.streamConsumerTask
            self.stream = nil
            self.connection = nil
            self.streamContinuation = nil
            self.streamConsumerTask = nil
            return (s, c, cont, task)
        }

        continuation?.finish()
        consumer?.cancel()
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
