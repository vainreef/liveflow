import SwiftUI
import AppKit

@MainActor
public final class WindowManager: NSObject, NSWindowDelegate {
    public static let shared = WindowManager()
    public weak var mainWindow: NSWindow?
    public var bottomPanelHeight: CGFloat = 190.0

    public func register(window: NSWindow) {
        self.mainWindow = window
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 800, height: 800 * 9.0 / 16.0 + 160.0)
    }

    public func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        }
    }

    public func hideMainWindow() {
        mainWindow?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    public func toggleMainWindow() {
        if let window = mainWindow, window.isVisible, NSApp.isActive {
            hideMainWindow()
        } else {
            showMainWindow()
        }
    }

    public func adjustBottomPanelHeight(deltaY: CGFloat) {
        guard let window = mainWindow else { return }
        var frame = window.frame
        let newBottom = min(max(150.0, bottomPanelHeight + deltaY), 450.0)
        let diff = newBottom - bottomPanelHeight
        bottomPanelHeight = newBottom

        frame.origin.y -= diff
        frame.size.height += diff
        window.setFrame(frame, display: true, animate: false)
    }

    // MARK: - NSWindowDelegate
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        // Hide from macOS Dock when window is closed
        NSApp.setActivationPolicy(.accessory)
        return false
    }

    public func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let titleBarHeight: CGFloat
        if let cv = sender.contentView {
            titleBarHeight = sender.frame.height - cv.frame.height
        } else {
            titleBarHeight = 28.0
        }

        // If width is resized (corner or side resize):
        // Automatically sync height = width * (9 / 16) + bottomPanelHeight
        // to mathematically guarantee ZERO black bars on all 4 sides of the monitor
        if abs(frameSize.width - sender.frame.width) > 1.0 {
            let contentWidth = frameSize.width
            let monitorHeight = contentWidth * (9.0 / 16.0)
            let targetContentHeight = monitorHeight + bottomPanelHeight
            return NSSize(width: frameSize.width, height: targetContentHeight + titleBarHeight)
        } else {
            // Pure vertical resize: user is resizing bottom panel
            let contentWidth = frameSize.width
            let monitorHeight = contentWidth * (9.0 / 16.0)
            let newBottom = (frameSize.height - titleBarHeight) - monitorHeight
            bottomPanelHeight = min(max(150.0, newBottom), 500.0)
            return frameSize
        }
    }
}

public struct WindowAccessor: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                WindowManager.shared.register(window: window)
            }
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window, WindowManager.shared.mainWindow == nil {
            WindowManager.shared.register(window: window)
        }
    }
}
