import SwiftUI
import MetalKit

public final class MTKPreviewView: MTKView, MTKViewDelegate {
    private weak var engine: StreamEngine?
    private var commandQueue: MTLCommandQueue?
    private var blitPipelineState: MTLRenderPipelineState?

    public init(engine: StreamEngine) {
        self.engine = engine
        let device = MTLCreateSystemDefaultDevice()!
        super.init(frame: .zero, device: device)

        self.delegate = self
        self.enableSetNeedsDisplay = false
        self.isPaused = false
        self.preferredFramesPerSecond = 60
        self.colorPixelFormat = .bgra8Unorm
        self.commandQueue = device.makeCommandQueue()

        setupBlitPipeline(device: device)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupBlitPipeline(device: MTLDevice) {
        let library = try? device.makeLibrary(source: ShaderSource.source, options: nil)
        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.vertexFunction = library?.makeFunction(name: "vertex_main")
        pipelineDesc.fragmentFunction = library?.makeFunction(name: "fragment_rgba")
        pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm

        if let pipelineDesc = try? device.makeRenderPipelineState(descriptor: pipelineDesc) {
            self.blitPipelineState = pipelineDesc
        }
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let engine = engine,
              let texture = engine.latestPreviewTexture,
              let drawable = view.currentDrawable,
              let passDesc = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc),
              let pipeline = blitPipelineState else {
            return
        }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)

        var uniforms = LayerUniforms(
            rect: SIMD4<Float>(0, 0, 1, 1),
            cropRect: SIMD4<Float>(0, 0, 1, 1),
            opacity: 1.0,
            flipY: 1.0
        )
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<LayerUniforms>.size, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<LayerUniforms>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

public struct MetalCanvasRepresentable: NSViewRepresentable {
    @ObservedObject var engine: StreamEngine

    public func makeNSView(context: Context) -> MTKPreviewView {
        MTKPreviewView(engine: engine)
    }

    public func updateNSView(_ nsView: MTKPreviewView, context: Context) {}
}
