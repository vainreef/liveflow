import SwiftUI

public struct MainWindowView: View {
    @StateObject private var engine = StreamEngine()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header stats status bar
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                    Text(statusTitle)
                        .font(.system(size: 13, weight: .bold))
                }

                Spacer()

                if engine.isLive {
                    HStack(spacing: 16) {
                        Label(String(format: "%.1f FPS", engine.stats.fps), systemImage: "speedometer")
                        Label(String(format: "%.0f kbps", engine.stats.bitrateKbps), systemImage: "network")
                        Label(formatUptime(engine.stats.uptimeSeconds), systemImage: "clock")
                        Label(formatBytes(engine.stats.totalBytesSent), systemImage: "arrow.up.circle")
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Metal Canvas View (16:9 Aspect Ratio)
            ZStack {
                Color.black
                MetalCanvasRepresentable(engine: engine)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
            }
            .frame(minHeight: 360)

            Divider()

            // Bottom controls
            StreamControlsView(engine: engine)
        }
        .frame(minWidth: 960, minHeight: 620)
    }

    private var statusColor: Color {
        switch engine.status {
        case .idle: return .gray
        case .connecting: return .yellow
        case .streaming: return .green
        case .error: return .red
        }
    }

    private var statusTitle: String {
        switch engine.status {
        case .idle: return "STANDBY"
        case .connecting: return "CONNECTING..."
        case .streaming: return "LIVE"
        case .error(let msg): return "ERROR: \(msg)"
        }
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let s = total % 60
        let m = (total / 60) % 60
        let h = total / 3600
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / (1024.0 * 1024.0)
        return String(format: "%.1f MB", mb)
    }
}
