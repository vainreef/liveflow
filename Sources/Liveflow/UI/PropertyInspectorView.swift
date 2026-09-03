import SwiftUI
import AppKit

/// Premiere Pro-style scrubbable numeric field.
/// Click and drag horizontally to smoothly adjust values with real-time visual feedback.
/// Supports Shift for 5x acceleration, Option for 0.1x precision, and double-click to type directly.
public struct ScrubbableNumberField: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let onCommit: () -> Void

    @State private var isHovered = false
    @State private var isDragging = false
    @State private var isEditing = false
    @State private var editText = ""
    @State private var dragAccumulated: CGFloat = 0

    public init(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1.0,
        unit: String = "",
        onCommit: @escaping () -> Void
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.onCommit = onCommit
    }

    public var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 38, alignment: .leading)

            if isEditing {
                TextField("", text: $editText, onCommit: {
                    if let val = Double(editText) {
                        value = min(max(range.lowerBound, val), range.upperBound)
                        onCommit()
                    }
                    isEditing = false
                })
                .textFieldStyle(.roundedBorder)
                .controlSize(.mini)
                .frame(height: 18)
            } else {
                HStack(spacing: 1) {
                    Text(String(format: "%.0f", value))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(isDragging ? .blue : (isHovered ? .accentColor : .primary))

                    if !unit.isEmpty {
                        Text(unit)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isDragging ? Color.blue.opacity(0.18) : (isHovered ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isDragging ? Color.blue : (isHovered ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2)), lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHovered = hovering
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { gesture in
                            if !isDragging {
                                isDragging = true
                                dragAccumulated = 0
                            }
                            let currentX = gesture.translation.width
                            let deltaX = currentX - dragAccumulated
                            dragAccumulated = currentX

                            var multiplier = 1.0
                            if NSEvent.modifierFlags.contains(.shift) {
                                multiplier = 5.0
                            } else if NSEvent.modifierFlags.contains(.option) {
                                multiplier = 0.1
                            }

                            let deltaValue = Double(deltaX) * step * multiplier
                            let newValue = min(max(range.lowerBound, value + deltaValue), range.upperBound)
                            if newValue != value {
                                value = newValue
                                onCommit()
                            }
                        }
                        .onEnded { _ in
                            isDragging = false
                            dragAccumulated = 0
                        }
                )
                .onTapGesture(count: 2) {
                    editText = String(format: "%.0f", value)
                    isEditing = true
                }
            }
        }
    }
}

/// Dedicated middle column property inspector for the selected SceneItem.
public struct PropertyInspectorView: View {
    @ObservedObject var engine: StreamEngine

    public init(engine: StreamEngine) {
        self.engine = engine
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Label("Property", systemImage: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .bold))

                Spacer()

                if let item = engine.selectedItem {
                    Text(item.name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
            }

            if let item = engine.selectedItem {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        // 1. Presets Bar
                        HStack(spacing: 5) {
                            Button("Fit (16:9)") {
                                engine.fitSelectedItem()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .help("Auto fit inside 16:9 canvas")

                            Button("Fill & Crop") {
                                engine.fillAndCropSelectedItem()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .help("Crop borders to fill 16:9 edge-to-edge")

                            Button("Reset") {
                                engine.resetSelectedItem()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .help("Reset position and crop")
                        }
                        .padding(.top, 1)

                        Divider()

                        // 2. Position & Size (Transform)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Transform")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)

                            HStack(spacing: 8) {
                                ScrubbableNumberField(
                                    label: "X",
                                    value: Binding(
                                        get: { item.pixelX },
                                        set: { item.pixelX = $0 }
                                    ),
                                    range: -1920...3840,
                                    step: 1.0,
                                    unit: "px"
                                ) {
                                    engine.updateSceneItems()
                                }

                                ScrubbableNumberField(
                                    label: "Y",
                                    value: Binding(
                                        get: { item.pixelY },
                                        set: { item.pixelY = $0 }
                                    ),
                                    range: -1080...2160,
                                    step: 1.0,
                                    unit: "px"
                                ) {
                                    engine.updateSceneItems()
                                }
                            }

                            HStack(spacing: 8) {
                                ScrubbableNumberField(
                                    label: "W",
                                    value: Binding(
                                        get: { item.pixelWidth },
                                        set: { item.pixelWidth = $0 }
                                    ),
                                    range: 20...3840,
                                    step: 1.0,
                                    unit: "px"
                                ) {
                                    engine.updateSceneItems()
                                }

                                ScrubbableNumberField(
                                    label: "H",
                                    value: Binding(
                                        get: { item.pixelHeight },
                                        set: { item.pixelHeight = $0 }
                                    ),
                                    range: 20...2160,
                                    step: 1.0,
                                    unit: "px"
                                ) {
                                    engine.updateSceneItems()
                                }
                            }
                        }

                        Divider()

                        // 3. Crop
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Crop")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)

                            HStack(spacing: 8) {
                                ScrubbableNumberField(
                                    label: "Left",
                                    value: Binding(
                                        get: { item.cropLeftPercent },
                                        set: { item.cropLeftPercent = $0 }
                                    ),
                                    range: 0...95,
                                    step: 0.5,
                                    unit: "%"
                                ) {
                                    engine.updateSceneItems()
                                }

                                ScrubbableNumberField(
                                    label: "Right",
                                    value: Binding(
                                        get: { item.cropRightPercent },
                                        set: { item.cropRightPercent = $0 }
                                    ),
                                    range: 0...95,
                                    step: 0.5,
                                    unit: "%"
                                ) {
                                    engine.updateSceneItems()
                                }
                            }

                            HStack(spacing: 8) {
                                ScrubbableNumberField(
                                    label: "Top",
                                    value: Binding(
                                        get: { item.cropTopPercent },
                                        set: { item.cropTopPercent = $0 }
                                    ),
                                    range: 0...95,
                                    step: 0.5,
                                    unit: "%"
                                ) {
                                    engine.updateSceneItems()
                                }

                                ScrubbableNumberField(
                                    label: "Bottom",
                                    value: Binding(
                                        get: { item.cropBottomPercent },
                                        set: { item.cropBottomPercent = $0 }
                                    ),
                                    range: 0...95,
                                    step: 0.5,
                                    unit: "%"
                                ) {
                                    engine.updateSceneItems()
                                }
                            }
                        }

                        Divider()

                        // 4. Opacity
                        HStack(spacing: 8) {
                            ScrubbableNumberField(
                                label: "Opacity",
                                value: Binding(
                                    get: { item.opacityPercent },
                                    set: { item.opacityPercent = $0 }
                                ),
                                range: 0...100,
                                step: 1.0,
                                unit: "%"
                            ) {
                                engine.updateSceneItems()
                            }
                        }
                    }
                    .padding(.trailing, 2)
                }
            } else {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "cursorarrow.and.square.on.square.dashed")
                        .font(.system(size: 22))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Select a source to inspect")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
