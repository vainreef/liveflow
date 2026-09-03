import Foundation
import CoreGraphics

/// An individual visual layer within the Metal scene graph.
public final class SceneItem: Identifiable, @unchecked Sendable {
    public let id: UUID
    public var name: String
    public var source: any VideoSource
    /// Position and size on canvas in normalized coordinates [0.0 ... 1.0] (x, y, width, height)
    public var rect: CGRect
    /// Crop rectangle on source texture in normalized coordinates [0.0 ... 1.0] (u, v, width, height)
    public var cropRect: CGRect
    public var opacity: Float
    public var zIndex: Int
    public var isEnabled: Bool
    public var nativeWidth: Int
    public var nativeHeight: Int

    public init(
        id: UUID = UUID(),
        name: String? = nil,
        source: any VideoSource,
        rect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
        cropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
        opacity: Float = 1.0,
        zIndex: Int = 0,
        isEnabled: Bool = true,
        nativeWidth: Int = 1920,
        nativeHeight: Int = 1080
    ) {
        self.id = id
        self.source = source
        self.name = name ?? source.name
        self.rect = rect
        self.cropRect = cropRect
        self.opacity = opacity
        self.zIndex = zIndex
        self.isEnabled = isEnabled
        self.nativeWidth = nativeWidth
        self.nativeHeight = nativeHeight
    }

    /// Fits the native aspect ratio inside 16:9 canvas without distortion (letterbox/pillarbox)
    public func fitToCanvas(canvasWidth: Int = 1920, canvasHeight: Int = 1080) {
        let canvasRatio = Double(canvasWidth) / Double(canvasHeight) // 16:9 = ~1.7778
        let sourceRatio = Double(nativeWidth) / Double(max(nativeHeight, 1))

        cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)

        if abs(sourceRatio - canvasRatio) < 0.01 {
            // Already 16:9
            rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        } else if sourceRatio < canvasRatio {
            // Narrower than 16:9 (e.g. 16:10 MacBook screen 1680x1050 or 4:3)
            let fitWidth = sourceRatio / canvasRatio
            let offsetX = (1.0 - fitWidth) / 2.0
            rect = CGRect(x: offsetX, y: 0.0, width: fitWidth, height: 1.0)
        } else {
            // Wider than 16:9 (e.g. 21:9 ultrawide)
            let fitHeight = canvasRatio / sourceRatio
            let offsetY = (1.0 - fitHeight) / 2.0
            rect = CGRect(x: 0.0, y: offsetY, width: 1.0, height: fitHeight)
        }
    }

    /// Crops excess margins and fills the 16:9 canvas edge-to-edge
    public func fillAndCrop(canvasWidth: Int = 1920, canvasHeight: Int = 1080) {
        let canvasRatio = Double(canvasWidth) / Double(canvasHeight) // 16:9 = ~1.7778
        let sourceRatio = Double(nativeWidth) / Double(max(nativeHeight, 1))

        rect = CGRect(x: 0, y: 0, width: 1, height: 1)

        if abs(sourceRatio - canvasRatio) < 0.01 {
            // Already 16:9
            cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        } else if sourceRatio < canvasRatio {
            // Narrower than 16:9 (e.g. 16:10 -> crop top & bottom equally)
            let visibleHeightRatio = sourceRatio / canvasRatio
            let cropY = (1.0 - visibleHeightRatio) / 2.0
            cropRect = CGRect(x: 0.0, y: cropY, width: 1.0, height: visibleHeightRatio)
        } else {
            // Wider than 16:9 (e.g. 21:9 -> crop left & right equally)
            let visibleWidthRatio = canvasRatio / sourceRatio
            let cropX = (1.0 - visibleWidthRatio) / 2.0
            cropRect = CGRect(x: cropX, y: 0.0, width: visibleWidthRatio, height: 1.0)
        }
    }

    /// Resets transform to full-canvas stretch with no crop
    public func resetTransform() {
        rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    /// Moves position on canvas by normalized delta
    public func move(dx: CGFloat, dy: CGFloat) {
        rect.origin.x = (rect.origin.x + dx).clamped(to: -1.0...1.0)
        rect.origin.y = (rect.origin.y + dy).clamped(to: -1.0...1.0)
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}
