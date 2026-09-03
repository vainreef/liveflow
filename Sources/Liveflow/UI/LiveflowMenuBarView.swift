import SwiftUI
import AppKit

public struct LiveflowMenuBarView: View {
    @ObservedObject var engine: StreamEngine

    public init(engine: StreamEngine) {
        self.engine = engine
    }

    public var body: some View {
        VStack {
            if engine.isLive {
                Text("LIVE • 1080p60 @ 15 Mbps")
                    .fontWeight(.bold)
                Text("\(String(format: "%.1f", engine.stats.fps)) FPS • \(String(format: "%.0f", engine.stats.bitrateKbps)) kbps")
            } else {
                Text("Liveflow: Standby")
                    .fontWeight(.medium)
            }

            Divider()

            Button("Show Main Window (⌥⌘0)") {
                WindowManager.shared.showMainWindow()
            }
            .keyboardShortcut("0", modifiers: [.command, .option])

            Divider()

            Button(engine.isLive ? "Stop Streaming (⌥⌘R)" : "Start Streaming (⌥⌘R)") {
                Task {
                    if engine.isLive {
                        await engine.stopStreaming()
                    } else {
                        await engine.startStreaming()
                    }
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .option])

            Button("Refresh Displays (⇧⌘R)") {
                Task { await engine.refreshDisplays() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Button("GitHub Repository") {
                if let url = URL(string: "https://github.com/vainreef/liveflow") {
                    NSWorkspace.shared.open(url)
                }
            }

            Button("Quit Liveflow (⌘Q)") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
    }
}
