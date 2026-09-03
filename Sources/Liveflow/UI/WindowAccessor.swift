import SwiftUI
import AppKit

@MainActor
public final class WindowManager: NSObject, NSWindowDelegate {
    public static let shared = WindowManager()
    public weak var mainWindow: NSWindow?

    public func register(window: NSWindow) {
        self.mainWindow = window
        window.delegate = self
        window.isReleasedWhenClosed = false
    }

    public func showMainWindow() {
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    public func hideMainWindow() {
        mainWindow?.orderOut(nil)
    }

    // MARK: - NSWindowDelegate
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false // Do not destroy window; hide to menu bar
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
