import SwiftUI

public struct StreamControlsView: View {
    @ObservedObject var engine: StreamEngine

    public init(engine: StreamEngine) {
        self.engine = engine
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // ========================================================
            // 1. Left Column: Sources List (Narrower width)
            // ========================================================
            VStack(alignment: .leading, spacing: 6) {
                // Header
                HStack {
                    Label("Sources", systemImage: "square.2.layers.3d")
                        .font(.system(size: 13, weight: .bold))

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

                // Sources List in a flexible container
                VStack(spacing: 0) {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 3) {
                            if engine.sceneItems.isEmpty {
                                Text("No sources.\nClick + to add.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity, minHeight: 70)
                            } else {
                                ForEach(engine.sceneItems) { item in
                                    let isSelected = (engine.selectedItemID == item.id)
                                    HStack(spacing: 5) {
                                        Text(item.name)
                                            .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                                            .foregroundColor(item.isEnabled ? .primary : .secondary)
                                            .lineLimit(1)

                                        Spacer(minLength: 2)

                                        Button {
                                            item.isEnabled.toggle()
                                            engine.updateSceneItems()
                                        } label: {
                                            Image(systemName: item.isEnabled ? "eye.fill" : "eye.slash")
                                                .font(.system(size: 10))
                                                .foregroundColor(item.isEnabled ? .accentColor : .secondary)
                                        }
                                        .buttonStyle(.plain)

                                        Button {
                                            Task { await engine.removeSceneItem(id: item.id) }
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 10))
                                                .foregroundColor(.red.opacity(0.8))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(isSelected ? Color.accentColor.opacity(0.18) : Color(NSColor.controlBackgroundColor))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        engine.selectedItemID = item.id
                                    }
                                }
                            }
                        }
                        .padding(4)
                    }
                    .frame(minHeight: 70, maxHeight: .infinity)
                }
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .cornerRadius(5)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }
            .frame(width: 195)

            Divider()

            // ========================================================
            // 2. Middle Column: Property Inspector (Scrubbable controls)
            // ========================================================
            PropertyInspectorView(engine: engine)
                .frame(maxWidth: .infinity)

            Divider()

            // ========================================================
            // 3. Right Column: Stream Destination (Top) & Audio (Bottom)
            // ========================================================
            VStack(alignment: .leading, spacing: 6) {
                // Header
                HStack {
                    Label("Stream Destination", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    if engine.isTestMode {
                        Text("Test Mode")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.indigo)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.indigo.opacity(0.12))
                            .cornerRadius(4)
                    } else {
                        Text("Live")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .cornerRadius(4)
                    }
                }

                // Stacked inputs: Server URL on top, Stream Key underneath
                VStack(alignment: .leading, spacing: 3) {
                    Text("Server URL:")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    TextField("rtmp://... (Leave empty to test)", text: $engine.rtmpURL)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .disabled(engine.isLive)

                    Text("Stream Key:")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    SecureField("key (Optional)", text: $engine.streamKey)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .disabled(engine.isLive)
                }

                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(engine.isTestMode ? "Pipeline Mode" : "Stream Spec")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text("1080p60 · 15M")
                            .font(.system(size: 10, weight: .bold))
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
                        HStack(spacing: 4) {
                            Image(systemName: engine.isLive ? "stop.fill" : (engine.isTestMode ? "waveform.badge.magnifyingglass" : "play.fill"))
                            Text(engine.isLive ? (engine.isDryRunTest ? "Stop Test" : "Stop Stream") : (engine.isTestMode ? "Test Stream" : "Start Stream"))
                                .fontWeight(.bold)
                                .font(.system(size: 11))
                        }
                        .frame(minWidth: 100, minHeight: 22)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(engine.isLive ? .red : (engine.isTestMode ? .indigo : .blue))
                }

                Divider()

                // Audio Mixer
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Label("Audio Mixer", systemImage: "waveform")
                            .font(.system(size: 12, weight: .bold))

                        Spacer()

                        Text("\(Int(engine.audioPeakLevel * 100))%")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 6) {
                        Text("Microphone")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .frame(width: 65, alignment: .leading)

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
                        .frame(height: 8)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(width: 280)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
