import SwiftUI

public struct MainWindowView: View {
    @ObservedObject var engine: StreamEngine

    public init(engine: StreamEngine) {
        self.engine = engine
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Permission Banner (if needed)
            if !engine.hasScreenPermission {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("Screen & System Audio Recording permission is required to capture display.")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Button("Open System Settings") {
                        PermissionHelper.requestScreenRecordingPermission()
                        PermissionHelper.openScreenRecordingSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Button("Check Again") {
                        Task { await engine.refreshDisplays() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Color.yellow.opacity(0.15))

                Divider()
            }

            // Error Banner (if any)
            if let errorMsg = engine.lastErrorMessage {
                HStack(spacing: 10) {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundColor(.red)
                    Text(errorMsg)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                    Spacer()
                    Button("Dismiss") {
                        engine.lastErrorMessage = nil
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Color.red.opacity(0.1))

                Divider()
            }

            // ========================================================
            // Top Section: 16:9 Monitor Viewport with Integrated HUD
            // ========================================================
            ZStack(alignment: .top) {
                // Black Background filling the monitor area
                Color.black

                // 16:9 Canvas
                MetalCanvasRepresentable(engine: engine)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)

                // Sleek Floating HUD Bar on top of the monitor
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusTitle)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.65))
                    .cornerRadius(4)

                    Spacer()

                    if engine.isLive {
                        HStack(spacing: 12) {
                            Label(String(format: "%.1f FPS", engine.stats.fps), systemImage: "speedometer")
                            Label(String(format: "%.0f kbps", engine.stats.bitrateKbps), systemImage: "network")
                            Label(formatUptime(engine.stats.uptimeSeconds), systemImage: "clock")
                            Label(formatBytes(engine.stats.totalBytesSent), systemImage: "arrow.up.circle")
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.65))
                        .cornerRadius(4)
                    }
                }
                .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // ========================================================
            // Bottom Section: All Control Panels
            // ========================================================
            StreamControlsView(engine: engine)
                .fixedSize(horizontal: false, vertical: true)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(minWidth: 860, minHeight: 600)
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
