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
        let minW: CGFloat = 780.0
        let minH: CGFloat = minW * (9.0 / 16.0) + 140.0 + 28.0
        window.minSize = NSSize(width: minW, height: minH)
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
            titleBarHeight = max(0, sender.frame.height - cv.frame.height)
        } else {
            titleBarHeight = 28.0
        }

        let currentWidth = sender.frame.width
        let currentHeight = sender.frame.height

        let widthChanged = abs(frameSize.width - currentWidth) > 0.5
        let heightChanged = abs(frameSize.height - currentHeight) > 0.5

        let minWidth: CGFloat = 780.0
        let minBottomHeight: CGFloat = 140.0

        // 1. 横向拉伸 (Horizontal Resize):
        // 整个窗口高度绝对不变，只改变下面部分的高度（监视器变大，下面自适应收缩，窗口总高度固定）
        if widthChanged && !heightChanged {
            let fixedHeight = currentHeight
            let availableContentHeight = fixedHeight - titleBarHeight

            // 顶格 16:9 监视器高度 = width * 9 / 16
            // 下方板块必须保留至少 minBottomHeight，因此宽度的上限为：
            let maxAllowedWidth = max(minWidth, (availableContentHeight - minBottomHeight) * (16.0 / 9.0))
            let clampedWidth = min(max(minWidth, frameSize.width), maxAllowedWidth)

            return NSSize(width: clampedWidth, height: fixedHeight)
        }

        // 2. 纵向拉伸 (Vertical Resize):
        // 宽度绝对不变，只改变下面部分的高度（监视器大小完全不变，所有拉伸空间全部提供给下方控制面板）
        if heightChanged && !widthChanged {
            let fixedWidth = currentWidth
            let monitorHeight = fixedWidth * (9.0 / 16.0)
            let minAllowedHeight = monitorHeight + minBottomHeight + titleBarHeight
            let clampedHeight = max(frameSize.height, minAllowedHeight)

            return NSSize(width: fixedWidth, height: clampedHeight)
        }

        // 3. 斜向拉伸 (Diagonal / Corner Resize):
        // 用户同时改变宽度与高度：
        // 宽度决定 16:9 监视器大小，高度在保证下方板块 >= minBottomHeight 的前提下自由拉伸
        if widthChanged && heightChanged {
            let clampedWidth = max(minWidth, frameSize.width)
            let monitorHeight = clampedWidth * (9.0 / 16.0)
            let minAllowedHeight = monitorHeight + minBottomHeight + titleBarHeight
            let clampedHeight = max(frameSize.height, minAllowedHeight)

            return NSSize(width: clampedWidth, height: clampedHeight)
        }

        return frameSize
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
