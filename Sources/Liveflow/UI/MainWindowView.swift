import SwiftUI

public struct MainWindowView: View {
    @ObservedObject var engine: StreamEngine

    public init(engine: StreamEngine) {
        self.engine = engine
    }

    public var body: some View {
        GeometryReader { geo in
            let windowWidth = geo.size.width
            let windowHeight = geo.size.height
            // Monitor height is strictly calculated from width to lock 16:9 and eliminate black bars
            let monitorHeight = windowWidth * (9.0 / 16.0)
            let bottomHeight = max(130.0, windowHeight - monitorHeight - 7.0)

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
                // 1. Top Section: 16:9 Monitor Viewport (Zero Black Bars)
                // ========================================================
                ZStack(alignment: .top) {
                    Color.black

                    MetalCanvasRepresentable(engine: engine)
                        .frame(width: windowWidth, height: monitorHeight)

                    // Floating HUD Bar hugging the top edge of the 16:9 frame
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
                .frame(width: windowWidth, height: monitorHeight)
                .clipped()

                // ========================================================
                // 2. Interactive Draggable Splitter Bar
                // ========================================================
                SplitterBar { deltaY in
                    WindowManager.shared.adjustBottomPanelHeight(deltaY: deltaY)
                }

                // ========================================================
                // 3. Bottom Section: All Control Panels
                // ========================================================
                StreamControlsView(engine: engine)
                    .frame(width: windowWidth, height: bottomHeight)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(minWidth: 800, minHeight: 610)
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

struct SplitterBar: View {
    var onDrag: (CGFloat) -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(height: 1)

            Capsule()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 36, height: 4)
        }
        .frame(height: 7)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { gesture in
                    onDrag(gesture.translation.height * 0.15)
                }
        )
    }
}
