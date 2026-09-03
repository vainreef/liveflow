import SwiftUI

public struct StreamControlsView: View {
    @ObservedObject var engine: StreamEngine

    public var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // ==========================================
            // 1. Left Column: Sources & Transform Panel
            // ==========================================
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack {
                    Label("Sources", systemImage: "square.2.layers.3d")
                        .font(.headline)

                    Spacer()

                    Menu {
                        Section("Displays") {
                            if engine.availableDisplays.isEmpty {
                                Button("No Displays Detected (Click to Refresh)") {
                                    Task { await engine.refreshDisplays() }
                                }
                            } else {
                                ForEach(engine.availableDisplays) { display in
                                    Button(display.name) {
                                        Task { await engine.addScreenCaptureSource(display: display) }
                                    }
                                }
                            }
                        }

                        Section("Other Sources") {
                            Button("Camera (PIP)") {
                                Task { try? await engine.addCameraSource() }
                            }

                            Button("Test Pattern") {
                                Task { await engine.addTestPatternSource() }
                            }
                        }

                        Divider()

                        Button("Refresh Displays") {
                            Task { await engine.refreshDisplays() }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // Sources List in a tidy card container
                VStack(spacing: 0) {
                    ScrollView(.vertical) {
                        VStack(spacing: 4) {
                            if engine.sceneItems.isEmpty {
                                Text("No sources added. Click + to add display.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 12)
                            } else {
                                ForEach(engine.sceneItems) { item in
                                    let isSelected = (engine.selectedItemID == item.id)
                                    HStack(spacing: 8) {
                                        Text(item.name)
                                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                            .foregroundColor(item.isEnabled ? .primary : .secondary)
                                            .lineLimit(1)

                                        Spacer()

                                        Button {
                                            item.isEnabled.toggle()
                                            engine.updateSceneItems()
                                        } label: {
                                            Image(systemName: item.isEnabled ? "eye.fill" : "eye.slash")
                                                .foregroundColor(item.isEnabled ? .accentColor : .secondary)
                                        }
                                        .buttonStyle(.plain)

                                        Button {
                                            Task { await engine.removeSceneItem(id: item.id) }
                                        } label: {
                                            Image(systemName: "trash")
                                                .foregroundColor(.red.opacity(0.8))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(isSelected ? Color.accentColor.opacity(0.18) : Color(NSColor.controlBackgroundColor))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        engine.selectedItemID = item.id
                                    }
                                }
                            }
                        }
                        .padding(6)
                    }
                    .frame(height: 96)
                }
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )

                // Transform & Crop Controls for Selected Item
                if let selected = engine.selectedItem {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("Transform: \(selected.name)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            Spacer()
                        }

                        HStack(spacing: 6) {
                            Button("Fit (16:9)") {
                                engine.fitSelectedItem()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .help("Preserve display aspect ratio inside 16:9 canvas")

                            Button("Fill & Crop") {
                                engine.fillAndCropSelectedItem()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .help("Crop borders to fill 16:9 canvas completely")

                            Button("Reset") {
                                engine.resetSelectedItem()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)

                            Spacer()

                            // Move Steppers
                            HStack(spacing: 2) {
                                Button {
                                    engine.moveSelectedItem(dx: -0.02, dy: 0)
                                } label: {
                                    Image(systemName: "arrow.left")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)

                                Button {
                                    engine.moveSelectedItem(dx: 0, dy: -0.02)
                                } label: {
                                    Image(systemName: "arrow.up")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)

                                Button {
                                    engine.moveSelectedItem(dx: 0, dy: 0.02)
                                } label: {
                                    Image(systemName: "arrow.down")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)

                                Button {
                                    engine.moveSelectedItem(dx: 0.02, dy: 0)
                                } label: {
                                    Image(systemName: "arrow.right")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                        }
                    }
                    .padding(6)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
                    .cornerRadius(5)
                }
            }
            .frame(width: 360)

            Divider()

            // ========================================================
            // 2. Right Column: Stream Destination (Top) & Audio (Bottom)
            // ========================================================
            VStack(alignment: .leading, spacing: 10) {
                // Top: Stream Destination
                VStack(alignment: .leading, spacing: 6) {
                    Label("Stream Destination", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.headline)

                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Server URL:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("rtmp://...", text: $engine.rtmpURL)
                                .textFieldStyle(.roundedBorder)
                                .disabled(engine.isLive)
                        }

                        VStack(alignment: .leading, spacing: 2) {
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
                            HStack(spacing: 6) {
                                Image(systemName: engine.isLive ? "stop.fill" : "play.fill")
                                Text(engine.isLive ? "Stop Streaming" : "Start Streaming")
                                    .fontWeight(.bold)
                            }
                            .frame(minWidth: 150, minHeight: 30)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(engine.isLive ? .red : .blue)
                    }
                }

                Divider()

                // Bottom: Audio Mixer (placed under Stream Destination)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Audio Mixer", systemImage: "waveform")
                            .font(.headline)

                        Spacer()

                        Text("Level: \(Int(engine.audioPeakLevel * 100))%")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 8) {
                        Text("Microphone")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.gray.opacity(0.25))

                                RoundedRectangle(cornerRadius: 3)
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
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
