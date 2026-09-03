import Foundation
import CoreMedia

/// Protocol defining any video source in the live streaming scene.
/// Whether screen, camera, image, video, plugin or test pattern.
public protocol VideoSource: AnyObject, Sendable {
    var id: UUID { get }
    var name: String { get }
    var isRunning: Bool { get }

    func start() async throws
    func stop() async
    func currentFrame() -> VideoFrame?
}
