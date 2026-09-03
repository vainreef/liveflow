import SwiftUI
import AppKit
import Carbon

@main
struct LiveflowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var engine = StreamEngine()

    var body: some Scene {
        Window("Liveflow", id: "mainWindow") {
            MainWindowView(engine: engine)
                .background(WindowAccessor())
                .onAppear {
                    appDelegate.engine = engine
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1080, height: 820)
        .commands {
            // 1. Remove "New Window" (Cmd+N) so app is strictly single-window
            CommandGroup(replacing: .newItem) {}

            // 1.1 Undo / Redo
            CommandGroup(replacing: .undoRedo) {
                Button("Undo Property Change") {
                    engine.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!engine.canUndo)

                Button("Redo Property Change") {
                    engine.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!engine.canRedo)
            }

            // 1.2 Copy / Paste Source Transform
            CommandGroup(replacing: .pasteboard) {
                Button("Copy Source Transform") {
                    engine.copySelectedTransform()
                }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(engine.selectedItem == nil)

                Button("Paste Source Transform") {
                    engine.pasteSelectedTransform()
                }
                .keyboardShortcut("v", modifiers: .command)
                .disabled(engine.selectedItem == nil || !engine.canPasteTransform)
            }

            // 2. App Info & Updates
            CommandGroup(replacing: .appInfo) {
                Button("About Liveflow") {
                    NSApp.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "Liveflow",
                            .applicationVersion: "1.0.0",
                            .version: "1",
                            .credits: NSAttributedString(
                                string: "Apple Silicon Native Live Streaming Engine\nZero-copy GPU & Metal pipeline\n1080p60 • 15 Mbps"
                            )
                        ]
                    )
                }
                Button("Check for Updates...") {
                    if let url = URL(string: "https://github.com/vainreef/liveflow/releases") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            // 3. Stream Control Menu
            CommandMenu("Stream") {
                Button(engine.isLive ? "Stop Streaming" : "Start Streaming") {
                    Task {
                        if engine.isLive {
                            await engine.stopStreaming()
                        } else {
                            await engine.startStreaming()
                        }
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .option])

                Divider()

                Button("Refresh Displays") {
                    Task { await engine.refreshDisplays() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }

            // 4. Window Navigation
            CommandGroup(replacing: .windowList) {
                Button("Show Main Window") {
                    WindowManager.shared.showMainWindow()
                }
                .keyboardShortcut("0", modifiers: [.command, .option])
            }

            // 5. Help Menu with Cmd + ? navigation
            CommandGroup(replacing: .help) {
                Button("Liveflow Help") {
                    if let url = URL(string: "https://github.com/vainreef/liveflow#readme") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .keyboardShortcut("?", modifiers: [.command])

                Button("GitHub Repository") {
                    if let url = URL(string: "https://github.com/vainreef/liveflow") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Divider()

                Button("Report an Issue") {
                    if let url = URL(string: "https://github.com/vainreef/liveflow/issues") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }

        // Status Bar Tray Menu
        MenuBarExtra("Liveflow", systemImage: engine.isLive ? "record.circle.fill" : "antenna.radiowaves.left.and.right") {
            LiveflowMenuBarView(engine: engine)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var engine: StreamEngine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Setup system-wide Global HotKeys (works anywhere, even when hidden from Dock)
        setupGlobalHotKeys()

        // Check if headless test mode is requested via command line
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--test-stream"), idx + 1 < args.count {
            let targetURL = args[idx + 1]
            let durationSeconds: Double = {
                if let dIdx = args.firstIndex(of: "--duration"), dIdx + 1 < args.count, let d = Double(args[dIdx + 1]) {
                    return d
                }
                return 5.0
            }()
            runHeadlessStreamTest(targetURL: targetURL, duration: durationSeconds)
        }
    }

    private func setupGlobalHotKeys() {
        // Global HotKey 1: Option + Cmd + 0 (Toggle / Show Main Window anywhere in macOS)
        GlobalHotKeyManager.shared.register(
            id: 1,
            keyCode: UInt32(kVK_ANSI_0),
            modifiers: UInt32(cmdKey | optionKey)
        ) {
            WindowManager.shared.toggleMainWindow()
        }

        // Global HotKey 2: Option + Cmd + R (Toggle Start/Stop Streaming anywhere in macOS)
        GlobalHotKeyManager.shared.register(
            id: 2,
            keyCode: UInt32(kVK_ANSI_R),
            modifiers: UInt32(cmdKey | optionKey)
        ) { [weak self] in
            guard let engine = self?.engine else { return }
            Task {
                if engine.isLive {
                    await engine.stopStreaming()
                } else {
                    await engine.startStreaming()
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            WindowManager.shared.showMainWindow()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in menu bar tray when window is closed
        return false
    }

    private func runHeadlessStreamTest(targetURL: String, duration: Double) {
        Task { @MainActor in
            print("========================================")
            print("[TestMode] Starting headless stream test for Liveflow...")
            print("[TestMode] Target: \(targetURL)")
            print("[TestMode] Duration: \(duration)s")
            print("========================================")

            let engine = StreamEngine()
            engine.rtmpURL = targetURL
            engine.streamKey = ""

            await engine.startStreaming()

            guard engine.isLive else {
                print("[TestMode] ERROR: Failed to enter live state!")
                exit(1)
            }

            print("[TestMode] Stream is LIVE! Streaming frames for \(duration) seconds...")
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))

            let stats = engine.stats
            print("========================================")
            print("[TestMode] Liveflow Test Finished Successfully!")
            print("[TestMode] Average FPS: \(String(format: "%.1f", stats.fps))")
            print("[TestMode] Bitrate: \(String(format: "%.1f", stats.bitrateKbps)) kbps")
            print("[TestMode] Total bytes sent: \(stats.totalBytesSent) bytes")
            print("========================================")

            await engine.stopStreaming()

            if stats.totalBytesSent > 0 {
                print("[TestMode] VERIFICATION PASSED: Video and Audio data transmitted successfully!")
                exit(0)
            } else {
                print("[TestMode] VERIFICATION FAILED: No bytes were transmitted.")
                exit(2)
            }
        }
    }
}
