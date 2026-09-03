import SwiftUI

public struct StreamControlsView: View {
    @ObservedObject var engine: StreamEngine

    public var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // 1. Sources Column
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Sources", systemImage: "square.2.layers.3d")
                        .font(.headline)
                    Spacer()
                    Menu {
                        Menu("Capture Display (选择显示屏)") {
                            if engine.availableDisplays.isEmpty {
                                Button("Refresh Displays (刷新显示器列表)") {
                                    Task { await engine.refreshDisplays() }
                                }
                            } else {
                                ForEach(engine.availableDisplays) { display in
                                    Button(display.name) {
                                        Task { await engine.addScreenCaptureSource(display: display) }
                                    }
                                }
                                Divider()
                                Button("Refresh List (刷新列表)") {
                                    Task { await engine.refreshDisplays() }
                                }
                            }
                        }

                        Button("Add Camera (PIP 摄像头)") {
                            Task { try? await engine.addCameraSource() }
                        }

                        Button("Add Test Pattern (测试彩条)") {
                            Task { await engine.addTestPatternSource() }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(engine.sceneItems) { item in
                            HStack {
                                Button {
                                    item.isEnabled.toggle()
                                } label: {
                                    Image(systemName: item.isEnabled ? "eye.fill" : "eye.slash")
                                        .foregroundColor(item.isEnabled ? .accentColor : .secondary)
                                }
                                .buttonStyle(.plain)

                                Text(item.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)

                                Spacer()

                                Button {
                                    Task { await engine.removeSceneItem(id: item.id) }
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                            .cornerRadius(6)
                        }
                    }
                }
                .frame(maxHeight: 140)
            }
            .frame(width: 220)

            Divider()

            // 2. Audio Meter Column
            VStack(alignment: .leading, spacing: 8) {
                Label("Audio Mixer", systemImage: "waveform")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Microphone")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.3))

                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.green, .yellow, .red]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * CGFloat(engine.audioPeakLevel))
                                .animation(.linear(duration: 0.05), value: engine.audioPeakLevel)
                        }
                    }
                    .frame(height: 12)
                }
                Spacer()
            }
            .frame(width: 160)

            Divider()

            // 3. RTMP Stream Settings Column
            VStack(alignment: .leading, spacing: 8) {
                Label("Stream Destination", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Server URL:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("rtmp://...", text: $engine.rtmpURL)
                            .textFieldStyle(.roundedBorder)
                            .disabled(engine.isLive)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Stream Key:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        SecureField("key", text: $engine.streamKey)
                            .textFieldStyle(.roundedBorder)
                            .disabled(engine.isLive)
                    }
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stream Spec")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        HStack(spacing: 6) {
                            Text("1080p60")
                                .font(.caption)
                                .fontWeight(.bold)
                            Text("·")
                                .foregroundColor(.secondary)
                            Text("15 Mbps")
                                .font(.caption)
                                .fontWeight(.bold)
                        }
                    }

                    Spacer()

                    Button {
                        Task {
                            if engine.isLive {
                                await engine.stopStreaming()
                            } else {
                                await engine.startStreaming()
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: engine.isLive ? "stop.fill" : "play.fill")
                            Text(engine.isLive ? "Stop Streaming" : "Start Streaming")
                                .fontWeight(.bold)
                        }
                        .frame(minWidth: 140, minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(engine.isLive ? .red : .blue)
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
