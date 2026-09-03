import SwiftUI
import AppKit

@main
struct LivestreamerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainWindowView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1080, height: 720)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

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

    private func runHeadlessStreamTest(targetURL: String, duration: Double) {
        Task { @MainActor in
            print("========================================")
            print("[TestMode] Starting headless stream test...")
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
            print("[TestMode] Test Finished Successfully!")
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
