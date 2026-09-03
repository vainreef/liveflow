import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

/// Hardware-accelerated VideoToolbox encoder for Apple Silicon live streaming.
/// Encodes raw CVPixelBuffers directly into compressed H.264 / HEVC CMSampleBuffers.
public final class VideoToolboxEncoder: @unchecked Sendable {
    public typealias OutputHandler = @Sendable (CMSampleBuffer) -> Void

    public let width: Int32
    public let height: Int32
    public let fps: Int32
    public let bitRate: Int32
    public let codec: CMVideoCodecType

    private var compressionSession: VTCompressionSession?
    private var _pixelBufferPool: CVPixelBufferPool?
    private var outputHandler: OutputHandler?
    private let lock = NSLock()
    private var isPrepared = false

    public var pixelBufferPool: CVPixelBufferPool? {
        lock.withLock { _pixelBufferPool }
    }

    public init(
        width: Int32 = 1920,
        height: Int32 = 1080,
        fps: Int32 = 60,
        bitRate: Int32 = 12_000_000, // 12 Mbps default for YouTube 1080p60 High Quality
        codec: CMVideoCodecType = kCMVideoCodecType_H264
    ) {
        self.width = width
        self.height = height
        self.fps = fps
        self.bitRate = bitRate
        self.codec = codec
    }

    deinit {
        invalidate()
    }

    public func setOutputHandler(_ handler: @escaping OutputHandler) {
        lock.withLock {
            outputHandler = handler
        }
    }

    public func prepare() throws {
        let shouldPrepare = lock.withLock { () -> Bool in
            guard !isPrepared else { return false }
            return true
        }
        guard shouldPrepare else { return }

        var session: VTCompressionSession?
        let callback: VTCompressionOutputCallback = { outputCallbackRefCon, _, status, infoFlags, sampleBuffer in
            guard status == noErr, let sampleBuffer = sampleBuffer, let refCon = outputCallbackRefCon else {
                return
            }
            let encoder = Unmanaged<VideoToolboxEncoder>.fromOpaque(refCon).takeUnretainedValue()
            encoder.handleEncodedSampleBuffer(sampleBuffer)
        }

        let refCon = Unmanaged.passUnretained(self).toOpaque()

        let encoderSpecs: [CFString: Any] = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true
        ]
        let bufferAttrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVImageBufferColorPrimariesKey: kCVImageBufferColorPrimaries_ITU_R_709_2,
            kCVImageBufferTransferFunctionKey: kCVImageBufferTransferFunction_ITU_R_709_2,
            kCVImageBufferYCbCrMatrixKey: kCVImageBufferYCbCrMatrix_ITU_R_709_2
        ]

        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: codec,
            encoderSpecification: encoderSpecs as CFDictionary,
            imageBufferAttributes: bufferAttrs as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: callback,
            refcon: refCon,
            compressionSessionOut: &session
        )

        guard status == noErr, let session = session else {
            throw NSError(domain: "Liveflow", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to create VTCompressionSession (code \(status))"])
        }

        // Configure properties for YouTube 1080p60 High Quality live streaming
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_H264EntropyMode, value: kVTH264EntropyMode_CABAC)

        // Target 12 Mbps average bitrate with ~14.4 Mbps peak guardrail (1,800,000 bytes / 1 sec)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitRate as CFNumber)
        let peakBytesPerSec = max(1_800_000, Int(Double(bitRate) * 1.2 / 8.0))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: [peakBytesPerSec, 1] as CFArray)

        // GOP: 120 frames at 60 fps (2.0 seconds keyframe interval)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: (fps * 2) as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: 2.0 as CFNumber)

        // B-Frames & Temporal Frame Reordering
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowTemporalCompression, value: kCFBooleanTrue)

        // Explicit Rec.709 color metadata
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ColorPrimaries, value: kCVImageBufferColorPrimaries_ITU_R_709_2)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_TransferFunction, value: kCVImageBufferTransferFunction_ITU_R_709_2)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_YCbCrMatrix, value: kCVImageBufferYCbCrMatrix_ITU_R_709_2)

        let prepStatus = VTCompressionSessionPrepareToEncodeFrames(session)
        guard prepStatus == noErr else {
            throw NSError(domain: "Liveflow", code: Int(prepStatus), userInfo: [NSLocalizedDescriptionKey: "Failed to prepare VTCompressionSession"])
        }

        let pool = VTCompressionSessionGetPixelBufferPool(session)

        lock.withLock {
            self.compressionSession = session
            self._pixelBufferPool = pool
            self.isPrepared = true
        }
    }

    public func encode(pixelBuffer: CVPixelBuffer, presentationTimeStamp: CMTime, duration: CMTime) {
        let session = lock.withLock { () -> VTCompressionSession? in
            guard isPrepared else { return nil }
            return compressionSession
        }
        guard let session = session else { return }

        var flags: VTEncodeInfoFlags = []
        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: duration,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: &flags
        )
    }

    private func handleEncodedSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        let handler = lock.withLock { outputHandler }
        handler?(sampleBuffer)
    }

    public func invalidate() {
        let sessionToInvalidate = lock.withLock { () -> VTCompressionSession? in
            guard let s = compressionSession else { return nil }
            compressionSession = nil
            _pixelBufferPool = nil
            isPrepared = false
            return s
        }

        if let session = sessionToInvalidate {
            VTCompressionSessionInvalidate(session)
        }
    }
}
