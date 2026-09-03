import Foundation
import CoreGraphics

/// An individual visual layer within the Metal scene graph.
public final class SceneItem: Identifiable, @unchecked Sendable {
    public let id: UUID
    public var name: String
    public var source: any VideoSource
    /// Position and size in normalized coordinates [0.0 ... 1.0]
    public var rect: CGRect
    public var opacity: Float
    public var zIndex: Int
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String? = nil,
        source: any VideoSource,
        rect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
        opacity: Float = 1.0,
        zIndex: Int = 0,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.source = source
        self.name = name ?? source.name
        self.rect = rect
        self.opacity = opacity
        self.zIndex = zIndex
        self.isEnabled = isEnabled
    }
}
