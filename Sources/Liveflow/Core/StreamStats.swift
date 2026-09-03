import Foundation

/// Real-time live streaming statistics.
public struct StreamStats: Sendable, Codable {
    public var fps: Double = 0.0
    public var bitrateKbps: Double = 0.0
    public var totalBytesSent: UInt64 = 0
    public var droppedFrames: Int = 0
    public var uptimeSeconds: TimeInterval = 0.0

    public init(fps: Double = 0.0, bitrateKbps: Double = 0.0, totalBytesSent: UInt64 = 0, droppedFrames: Int = 0, uptimeSeconds: TimeInterval = 0.0) {
        self.fps = fps
        self.bitrateKbps = bitrateKbps
        self.totalBytesSent = totalBytesSent
        self.droppedFrames = droppedFrames
        self.uptimeSeconds = uptimeSeconds
    }
}
