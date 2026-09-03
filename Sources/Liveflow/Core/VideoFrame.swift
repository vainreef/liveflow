import Foundation
import CoreVideo
import CoreMedia
import Metal
import IOSurface
import QuartzCore

/// Represents a video frame backed by an IOSurface or CVPixelBuffer.
/// Pixels remain in GPU memory / IOSurface without CPU copy.
public final class VideoFrame: @unchecked Sendable {
    public let pixelBuffer: CVPixelBuffer
    public let timestamp: CMTime
    public let width: Int
    public let height: Int
    public let pixelFormat: OSType

    public var surface: IOSurface? {
        CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
    }

    public init(pixelBuffer: CVPixelBuffer, timestamp: CMTime = CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 60000)) {
        self.pixelBuffer = pixelBuffer
        self.timestamp = timestamp
        self.width = CVPixelBufferGetWidth(pixelBuffer)
        self.height = CVPixelBufferGetHeight(pixelBuffer)
        self.pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
    }

    /// Creates a Metal texture from the underlying CVPixelBuffer using CVMetalTextureCache (zero-copy live binding).
    public func makeTexture(cache: CVMetalTextureCache, planeIndex: Int = 0) -> MTLTexture? {
        let planeWidth = CVPixelBufferIsPlanar(pixelBuffer) ? CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex) : width
        let planeHeight = CVPixelBufferIsPlanar(pixelBuffer) ? CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex) : height

        let mtlPixelFormat: MTLPixelFormat
        switch pixelFormat {
        case kCVPixelFormatType_32BGRA:
            mtlPixelFormat = .bgra8Unorm
        case kCVPixelFormatType_32ARGB:
            mtlPixelFormat = .bgra8Unorm
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            mtlPixelFormat = (planeIndex == 0) ? .r8Unorm : .rg8Unorm
        default:
            mtlPixelFormat = .bgra8Unorm
        }

        var cvMetalTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            mtlPixelFormat,
            planeWidth,
            planeHeight,
            planeIndex,
            &cvMetalTexture
        )

        guard status == kCVReturnSuccess, let cvMetalTexture = cvMetalTexture else {
            return nil
        }

        return CVMetalTextureGetTexture(cvMetalTexture)
    }
}
