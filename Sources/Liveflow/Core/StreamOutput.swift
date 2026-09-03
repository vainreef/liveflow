import Foundation
import CoreMedia
import AVFoundation

/// Protocol for all streaming destinations (RTMP, SRT, WHIP, Recording, etc.)
public protocol StreamOutput: AnyObject, Sendable {
    var isStreaming: Bool { get }
    var stats: StreamStats { get }

    func connect(url: URL, streamKey: String?) async throws
    func sendVideo(sampleBuffer: CMSampleBuffer)
    func sendAudio(buffer: AVAudioBuffer, when: AVAudioTime)
    func disconnect() async
}
