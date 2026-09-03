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
                        Button("Add Screen Capture") {
                            Task { try? await engine.addScreenCaptureSource() }
                        }
                        Button("Add Camera (PIP)") {
                            Task { try? await engine.addCameraSource() }
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

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Resolution")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(engine.canvasWidth)x\(engine.canvasHeight) @ \(engine.targetFPS)fps")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }

                    Menu {
                        Button("15 Mbps (15,000 kbps) - 推荐高码率") { engine.targetBitrateKbps = 15000 }
                        Button("20 Mbps (20,000 kbps) - 4K/极高清") { engine.targetBitrateKbps = 20000 }
                        Button("12 Mbps (12,000 kbps) - 进阶画质") { engine.targetBitrateKbps = 12000 }
                        Button("8 Mbps (8,000 kbps) - 标准画质") { engine.targetBitrateKbps = 8000 }
                        Button("6 Mbps (6,000 kbps) - 均衡画质") { engine.targetBitrateKbps = 6000 }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bitrate")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(engine.targetBitrateKbps >= 1000 ? "\(engine.targetBitrateKbps / 1000) Mbps" : "\(engine.targetBitrateKbps) kbps")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .disabled(engine.isLive)

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
