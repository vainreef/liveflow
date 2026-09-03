import Foundation
@preconcurrency import Metal
@preconcurrency import CoreVideo
import CoreMedia
import simd

public struct LayerUniforms {
    public var rect: SIMD4<Float>     // x, y, width, height in normalized [0, 1]
    public var cropRect: SIMD4<Float> // u, v, width, height in normalized [0, 1]
    public var opacity: Float
    public var flipY: Float
    public var padding: SIMD2<Float> = .zero

    public init(rect: SIMD4<Float>, cropRect: SIMD4<Float> = SIMD4<Float>(0, 0, 1, 1), opacity: Float, flipY: Float = 1.0) {
        self.rect = rect
        self.cropRect = cropRect
        self.opacity = opacity
        self.flipY = flipY
    }
}

/// High-performance Metal scene compositor.
/// Merges all active sources into a single canvas frame in one command buffer.
public final class MetalSceneRenderer: @unchecked Sendable {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public private(set) var textureCache: CVMetalTextureCache!

    public let width: Int
    public let height: Int

    private var rgbaPipelineState: MTLRenderPipelineState!
    private var nv12PipelineState: MTLRenderPipelineState!
    private var samplerState: MTLSamplerState!
    private var outputPixelBufferPool: CVPixelBufferPool?

    public init(device: MTLDevice? = nil, width: Int = 1920, height: Int = 1080) {
        let dev = device ?? MTLCreateSystemDefaultDevice()!
        self.device = dev
        self.commandQueue = dev.makeCommandQueue()!
        self.width = width
        self.height = height

        setupTextureCache()
        setupPipeline()
        setupBufferPool()
    }

    private func setupTextureCache() {
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    }

    private func setupPipeline() {
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: ShaderSource.source, options: nil)
        } catch {
            fatalError("Failed to compile Metal shaders: \(error)")
        }

        let vertexFunc = library.makeFunction(name: "vertex_main")
        let rgbaFragFunc = library.makeFunction(name: "fragment_rgba")
        let nv12FragFunc = library.makeFunction(name: "fragment_nv12")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunc
        pipelineDescriptor.fragmentFunction = rgbaFragFunc
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            self.rgbaPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            pipelineDescriptor.fragmentFunction = nv12FragFunc
            self.nv12PipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create pipeline states: \(error)")
        }

        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        self.samplerState = device.makeSamplerState(descriptor: samplerDesc)
    }

    private let poolLock = NSLock()
    private var _externalPixelBufferPool: CVPixelBufferPool?

    public func setExternalPixelBufferPool(_ pool: CVPixelBufferPool?) {
        poolLock.withLock {
            _externalPixelBufferPool = pool
        }
    }

    public var activePixelBufferPool: CVPixelBufferPool? {
        poolLock.withLock { _externalPixelBufferPool } ?? outputPixelBufferPool
    }

    private func setupBufferPool() {
        let poolAttrs: [CFString: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey: 4
        ]
        let bufferAttrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferMetalCompatibilityKey: true
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttrs as CFDictionary, bufferAttrs as CFDictionary, &outputPixelBufferPool)
    }

    /// Asynchronously renders the scene into an offscreen CVPixelBuffer without blocking the calling CPU thread.
    /// Delivers the rendered buffer and preview texture on GPU completion via addCompletedHandler.
    public func renderOffscreenAsync(
        items: [SceneItem],
        timestamp: CMTime,
        completion: @escaping @Sendable (CVPixelBuffer, MTLTexture) -> Void
    ) -> Bool {
        guard let pool = activePixelBufferPool else { return false }
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return false }

        var cvMetalTexture: CVMetalTexture?
        let cvStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            buffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvMetalTexture
        )
        guard cvStatus == kCVReturnSuccess,
              let cvMetalTexture = cvMetalTexture,
              let targetTexture = CVMetalTextureGetTexture(cvMetalTexture) else {
            return false
        }

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = targetTexture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)
        passDesc.colorAttachments[0].storeAction = .store

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc) else {
            return false
        }

        encodeScene(items: items, in: encoder)
        encoder.endEncoding()

        commandBuffer.addCompletedHandler { _ in
            completion(buffer, targetTexture)
        }
        commandBuffer.commit()
        return true
    }

    /// Renders the scene into an offscreen IOSurface-backed CVPixelBuffer and Metal texture synchronously.
    public func renderOffscreen(items: [SceneItem], timestamp: CMTime) -> (CVPixelBuffer, MTLTexture)? {
        guard let pool = activePixelBufferPool else { return nil }
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        // Create Metal texture from CVPixelBuffer
        var cvMetalTexture: CVMetalTexture?
        let cvStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            buffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvMetalTexture
        )
        guard cvStatus == kCVReturnSuccess,
              let cvMetalTexture = cvMetalTexture,
              let targetTexture = CVMetalTextureGetTexture(cvMetalTexture) else {
            return nil
        }

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = targetTexture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)
        passDesc.colorAttachments[0].storeAction = .store

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc) else {
            return nil
        }

        encodeScene(items: items, in: encoder)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return (buffer, targetTexture)
    }

    /// Renders scene directly to an on-screen drawable texture (for MTKView preview).
    public func renderToDrawable(items: [SceneItem], drawableTexture: MTLTexture, in commandBuffer: MTLCommandBuffer) {
        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = drawableTexture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)
        passDesc.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc) else { return }
        encodeScene(items: items, in: encoder)
        encoder.endEncoding()
    }

    private func encodeScene(items: [SceneItem], in encoder: MTLRenderCommandEncoder) {
        encoder.setFragmentSamplerState(samplerState, index: 0)

        // Sort items by zIndex
        let sorted = items.filter { $0.isEnabled }.sorted { $0.zIndex < $1.zIndex }

        for item in sorted {
            guard let frame = item.source.currentFrame() else { continue }

            let r = item.renderedRect
            let c = item.renderedCropRect
            var uniforms = LayerUniforms(
                rect: SIMD4<Float>(Float(r.origin.x), Float(r.origin.y), Float(r.size.width), Float(r.size.height)),
                cropRect: SIMD4<Float>(Float(c.origin.x), Float(c.origin.y), Float(c.size.width), Float(c.size.height)),
                opacity: item.opacity,
                flipY: 1.0
            )
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<LayerUniforms>.size, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<LayerUniforms>.size, index: 0)

            if frame.pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
               frame.pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
                // NV12 Y + CbCr planes
                guard let yTex = frame.makeTexture(cache: textureCache, planeIndex: 0),
                      let uvTex = frame.makeTexture(cache: textureCache, planeIndex: 1) else { continue }
                encoder.setRenderPipelineState(nv12PipelineState)
                encoder.setFragmentTexture(yTex, index: 0)
                encoder.setFragmentTexture(uvTex, index: 1)
            } else {
                // BGRA / RGBA
                guard let tex = frame.makeTexture(cache: textureCache, planeIndex: 0) else { continue }
                encoder.setRenderPipelineState(rgbaPipelineState)
                encoder.setFragmentTexture(tex, index: 0)
            }

            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
    }
}
