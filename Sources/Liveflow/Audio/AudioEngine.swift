import Foundation
import AVFoundation

/// CoreAudio / AVAudioEngine capture and mixer for microphone and system audio.
public final class AudioEngine: @unchecked Sendable {
    public typealias AudioOutputHandler = @Sendable (AVAudioBuffer, AVAudioTime) -> Void

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var isRunning = false
    private var outputHandler: AudioOutputHandler?

    /// Current peak audio level (0.0 to 1.0) for UI VU meter
    private var _peakLevel: Float = 0.0
    public var peakLevel: Float {
        lock.withLock { _peakLevel }
    }

    public init() {}

    public func setOutputHandler(_ handler: @escaping AudioOutputHandler) {
        lock.withLock {
            self.outputHandler = handler
        }
    }

    public func start() throws {
        let shouldStart = lock.withLock { () -> Bool in
            guard !isRunning else { return false }
            isRunning = true
            return true
        }
        guard shouldStart else { return }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            guard let self = self else { return }

            if let floatData = buffer.floatChannelData {
                let frameLength = Int(buffer.frameLength)
                var maxSample: Float = 0.0
                let channelData = floatData[0]
                for i in 0..<frameLength {
                    let sample = abs(channelData[i])
                    if sample > maxSample {
                        maxSample = sample
                    }
                }
                let handler = self.lock.withLock { () -> AudioOutputHandler? in
                    self._peakLevel = min(maxSample, 1.0)
                    return self.outputHandler
                }

                // Stereo dual-channel broadcast: replicate mono into Left and Right channels (L = Mic, R = Mic)
                if format.channelCount == 1,
                   let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 2),
                   let stereoBuffer = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: buffer.frameLength) {
                    stereoBuffer.frameLength = buffer.frameLength
                    if let stereoData = stereoBuffer.floatChannelData {
                        let byteCount = frameLength * MemoryLayout<Float>.size
                        memcpy(stereoData[0], channelData, byteCount)
                        memcpy(stereoData[1], channelData, byteCount)
                    }
                    handler?(stereoBuffer, time)
                } else {
                    handler?(buffer, time)
                }
            }
        }

        try engine.start()
        print("[AudioEngine] Audio capture started with format: \(format)")
    }

    public func stop() {
        let shouldStop = lock.withLock { () -> Bool in
            guard isRunning else { return false }
            isRunning = false
            return true
        }
        guard shouldStop else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        print("[AudioEngine] Audio capture stopped.")
    }
}
