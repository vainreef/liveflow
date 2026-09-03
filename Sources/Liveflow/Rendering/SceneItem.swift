import Foundation
import CoreGraphics

/// An individual visual layer within the Metal scene graph.
public final class SceneItem: Identifiable, @unchecked Sendable {
    public let id: UUID
    public var name: String
    public var source: any VideoSource
    /// Position and size on canvas in normalized coordinates [0.0 ... 1.0] (x, y, width, height) before edge crop
    public var rect: CGRect
    /// Base UV crop (e.g. for fillAndCrop aspect ratio matching)
    public var baseCropRect: CGRect
    /// Normalized edge crop margins [0.0 ... 1.0]
    public var cropLeft: CGFloat = 0.0
    public var cropRight: CGFloat = 0.0
    public var cropTop: CGFloat = 0.0
    public var cropBottom: CGFloat = 0.0

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
        baseCropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
        cropLeft: CGFloat = 0.0,
        cropRight: CGFloat = 0.0,
        cropTop: CGFloat = 0.0,
        cropBottom: CGFloat = 0.0,
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
        self.baseCropRect = baseCropRect
        self.cropLeft = cropLeft
        self.cropRight = cropRight
        self.cropTop = cropTop
        self.cropBottom = cropBottom
        self.opacity = opacity
        self.zIndex = zIndex
        self.isEnabled = isEnabled
        self.nativeWidth = nativeWidth
        self.nativeHeight = nativeHeight
    }

    /// Convenience for compatibility
    public var cropRect: CGRect {
        get { renderedCropRect }
        set { baseCropRect = newValue }
    }

    // MARK: - Rendered Geometry (True Edge Crop with Zero Distortion / Stretch)
    /// Actual visible quad on the canvas. As margins are cropped, the quad shrinks on screen,
    /// cutting off the edges while maintaining the exact pixel scale and position of visible content.
    public var renderedRect: CGRect {
        let effectiveX = rect.origin.x + cropLeft * rect.size.width
        let effectiveY = rect.origin.y + cropTop * rect.size.height
        let effectiveW = max(0.0001, rect.size.width * (1.0 - cropLeft - cropRight))
        let effectiveH = max(0.0001, rect.size.height * (1.0 - cropTop - cropBottom))
        return CGRect(x: effectiveX, y: effectiveY, width: effectiveW, height: effectiveH)
    }

    /// Actual UV coordinates sampled from source texture, mathematically matching renderedRect
    /// so the content scale ratio (renderedRect.width / renderedCropRect.width) is strictly constant.
    public var renderedCropRect: CGRect {
        let u = baseCropRect.origin.x + cropLeft * baseCropRect.size.width
        let v = baseCropRect.origin.y + cropTop * baseCropRect.size.height
        let w = max(0.0001, baseCropRect.size.width * (1.0 - cropLeft - cropRight))
        let h = max(0.0001, baseCropRect.size.height * (1.0 - cropTop - cropBottom))
        return CGRect(x: u, y: v, width: w, height: h)
    }

    /// Fits the native aspect ratio inside 16:9 canvas without distortion (letterbox/pillarbox)
    public func fitToCanvas(canvasWidth: Int = 1920, canvasHeight: Int = 1080) {
        let canvasRatio = Double(canvasWidth) / Double(canvasHeight) // 16:9 = ~1.7778
        let sourceRatio = Double(nativeWidth) / Double(max(nativeHeight, 1))

        baseCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        cropLeft = 0.0
        cropRight = 0.0
        cropTop = 0.0
        cropBottom = 0.0

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
        cropLeft = 0.0
        cropRight = 0.0
        cropTop = 0.0
        cropBottom = 0.0

        if abs(sourceRatio - canvasRatio) < 0.01 {
            // Already 16:9
            baseCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        } else if sourceRatio < canvasRatio {
            // Narrower than 16:9 (e.g. 16:10 -> crop top & bottom equally)
            let visibleHeightRatio = sourceRatio / canvasRatio
            let cropY = (1.0 - visibleHeightRatio) / 2.0
            baseCropRect = CGRect(x: 0.0, y: cropY, width: 1.0, height: visibleHeightRatio)
        } else {
            // Wider than 16:9 (e.g. 21:9 -> crop left & right equally)
            let visibleWidthRatio = canvasRatio / sourceRatio
            let cropX = (1.0 - visibleWidthRatio) / 2.0
            baseCropRect = CGRect(x: cropX, y: 0.0, width: visibleWidthRatio, height: 1.0)
        }
    }

    /// Resets transform to full-canvas stretch with no crop
    public func resetTransform() {
        rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        baseCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        cropLeft = 0.0
        cropRight = 0.0
        cropTop = 0.0
        cropBottom = 0.0
    }

    /// Moves position on canvas by normalized delta
    public func move(dx: CGFloat, dy: CGFloat) {
        rect.origin.x = (rect.origin.x + dx).clamped(to: -1.0...1.0)
        rect.origin.y = (rect.origin.y + dy).clamped(to: -1.0...1.0)
    }

    // MARK: - Pixel & Percentage Accessors for Property Inspector
    public var pixelX: Double {
        get { Double(rect.origin.x * 1920.0) }
        set { rect.origin.x = CGFloat(newValue / 1920.0) }
    }
    public var pixelY: Double {
        get { Double(rect.origin.y * 1080.0) }
        set { rect.origin.y = CGFloat(newValue / 1080.0) }
    }
    public var pixelWidth: Double {
        get { Double(rect.size.width * 1920.0) }
        set { rect.size.width = CGFloat(max(10.0, newValue) / 1920.0) }
    }
    public var pixelHeight: Double {
        get { Double(rect.size.height * 1080.0) }
        set { rect.size.height = CGFloat(max(10.0, newValue) / 1080.0) }
    }

    public var cropLeftPercent: Double {
        get { Double(cropLeft * 100.0) }
        set {
            let val = CGFloat(newValue / 100.0).clamped(to: 0.0...0.95)
            cropLeft = min(val, 0.95 - cropRight)
        }
    }
    public var cropRightPercent: Double {
        get { Double(cropRight * 100.0) }
        set {
            let val = CGFloat(newValue / 100.0).clamped(to: 0.0...0.95)
            cropRight = min(val, 0.95 - cropLeft)
        }
    }
    public var cropTopPercent: Double {
        get { Double(cropTop * 100.0) }
        set {
            let val = CGFloat(newValue / 100.0).clamped(to: 0.0...0.95)
            cropTop = min(val, 0.95 - cropBottom)
        }
    }
    public var cropBottomPercent: Double {
        get { Double(cropBottom * 100.0) }
        set {
            let val = CGFloat(newValue / 100.0).clamped(to: 0.0...0.95)
            cropBottom = min(val, 0.95 - cropTop)
        }
    }
    public var opacityPercent: Double {
        get { Double(opacity * 100.0) }
        set { opacity = Float(newValue / 100.0).clamped(to: 0.0...1.0) }
    }
}

/// Snapshot of transform, crop, and opacity for undo/redo and copy/paste
public struct SceneItemTransformSnapshot: Equatable, Sendable {
    public var rect: CGRect
    public var baseCropRect: CGRect
    public var cropLeft: CGFloat
    public var cropRight: CGFloat
    public var cropTop: CGFloat
    public var cropBottom: CGFloat
    public var opacity: Float

    public init(
        rect: CGRect,
        baseCropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
        cropLeft: CGFloat = 0.0,
        cropRight: CGFloat = 0.0,
        cropTop: CGFloat = 0.0,
        cropBottom: CGFloat = 0.0,
        opacity: Float = 1.0
    ) {
        self.rect = rect
        self.baseCropRect = baseCropRect
        self.cropLeft = cropLeft
        self.cropRight = cropRight
        self.cropTop = cropTop
        self.cropBottom = cropBottom
        self.opacity = opacity
    }

    public init(from item: SceneItem) {
        self.rect = item.rect
        self.baseCropRect = item.baseCropRect
        self.cropLeft = item.cropLeft
        self.cropRight = item.cropRight
        self.cropTop = item.cropTop
        self.cropBottom = item.cropBottom
        self.opacity = item.opacity
    }

    public func apply(to item: SceneItem) {
        item.rect = self.rect
        item.baseCropRect = self.baseCropRect
        item.cropLeft = self.cropLeft
        item.cropRight = self.cropRight
        item.cropTop = self.cropTop
        item.cropBottom = self.cropBottom
        item.opacity = self.opacity
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}
