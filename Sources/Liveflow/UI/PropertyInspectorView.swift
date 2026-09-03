import SwiftUI
import AppKit

/// High-performance scrubbable number field built on native SwiftUI TextField.
/// - Single Click: Instantly enters editing, auto-selects all text in macOS blue selection, ready to type.
/// - Click & Drag: Smooth horizontal scrubbing with Shift (5x) and Option (0.1x) precision.
/// - Enter: Commits new value and updates scene.
/// - Esc / Click Outside: Cancels without applying, reverts cleanly.
/// - Normal state: Clean system text color (not permanently blue).
public struct ScrubbableNumberField: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let onDragStart: (() -> Void)?
    let onDragEnd: (() -> Void)?
    let onCommit: () -> Void

    @State private var isEditing = false
    @State private var text = ""
    @FocusState private var isFocused: Bool

    @State private var isHovered = false
    @State private var isDragging = false
    @State private var dragStartVal: Double = 0

    public init(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1.0,
        unit: String = "",
        onDragStart: (() -> Void)? = nil,
        onDragEnd: (() -> Void)? = nil,
        onCommit: @escaping () -> Void
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.onDragStart = onDragStart
        self.onDragEnd = onDragEnd
        self.onCommit = onCommit
    }

    public var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .leading)
                .lineLimit(1)

            ZStack(alignment: .trailing) {
                if isEditing {
                    TextField("", text: $text)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(NSColor.textBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.accentColor, lineWidth: 1.5)
                        )
                        .onSubmit {
                            if let val = Double(text) {
                                let clamped = min(max(range.lowerBound, val), range.upperBound)
                                if clamped != value {
                                    value = clamped
                                    onCommit()
                                }
                            }
                            isEditing = false
                        }
                        .onExitCommand {
                            // Esc key pressed -> cancel
                            isEditing = false
                        }
                        .onChange(of: isFocused) { _, focused in
                            if !focused {
                                // Lost focus / clicked outside -> cancel
                                isEditing = false
                            }
                        }
                } else {
                    HStack(spacing: 2) {
                        Text(String(format: "%.0f", value))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(isDragging ? .accentColor : .primary)

                        if !unit.isEmpty {
                            Text(unit)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isDragging ? Color.accentColor.opacity(0.18) : (isHovered ? Color.secondary.opacity(0.12) : Color(NSColor.controlBackgroundColor)))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(isDragging ? Color.accentColor : (isHovered ? Color.secondary.opacity(0.4) : Color.secondary.opacity(0.2)), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        guard !isEditing else { return }
                        isHovered = hovering
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                guard !isEditing else { return }
                                if !isDragging && abs(gesture.translation.width) >= 3 {
                                    isDragging = true
                                    dragStartVal = value
                                    onDragStart?()
                                }
                                if isDragging {
                                    let delta = gesture.translation.width
                                    var mult = 1.0
                                    if NSEvent.modifierFlags.contains(.shift) {
                                        mult = 5.0
                                    } else if NSEvent.modifierFlags.contains(.option) {
                                        mult = 0.1
                                    }
                                    let deltaVal = Double(delta) * step * mult
                                    let newVal = min(max(range.lowerBound, dragStartVal + deltaVal), range.upperBound)
                                    if newVal != value {
                                        value = newVal
                                        onCommit()
                                    }
                                }
                            }
                            .onEnded { gesture in
                                guard !isEditing else { return }
                                if isDragging {
                                    isDragging = false
                                    onDragEnd?()
                                } else {
                                    // SINGLE CLICK DETECTED -> ENTER EDIT MODE!
                                    text = String(format: "%.0f", value)
                                    isEditing = true
                                    isFocused = true
                                    // Auto-select all text so typing immediately replaces it
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                                    }
                                }
                            }
                    )
                }
            }
            .frame(height: 20)
        }
    }
}

/// Dedicated middle column property inspector for the selected SceneItem.
/// Integrates Premiere-style scrubbable controls, Undo / Redo history, and Copy / Paste.
public struct PropertyInspectorView: View {
    @ObservedObject var engine: StreamEngine

    @State private var dragStartSnapshot: SceneItemTransformSnapshot?

    public init(engine: StreamEngine) {
        self.engine = engine
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with Undo / Redo and Copy / Paste controls
            HStack(spacing: 6) {
                Label("Property", systemImage: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .bold))

                Spacer()

                // Undo Button (Cmd+Z)
                Button {
                    engine.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .disabled(!engine.canUndo)
                .help("Undo property change (⌘Z)")

                // Redo Button (Cmd+Shift+Z)
                Button {
                    engine.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .disabled(!engine.canRedo)
                .help("Redo property change (⇧⌘Z)")

                Divider().frame(height: 12)

                // Copy Transform (Cmd+C)
                Button {
                    engine.copySelectedTransform()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .disabled(engine.selectedItem == nil)
                .help("Copy source transform (⌘C)")

                // Paste Transform (Cmd+V)
                Button {
                    engine.pasteSelectedTransform()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .disabled(engine.selectedItem == nil || !engine.canPasteTransform)
                .help("Paste source transform (⌘V)")
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

                        // 2. Position & Scale (Transform)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Transform")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)

                            HStack(spacing: 8) {
                                ScrubbableNumberField(
                                    label: "Pos X",
                                    value: Binding(
                                        get: { item.pixelX },
                                        set: { item.pixelX = $0 }
                                    ),
                                    range: -1920...3840,
                                    step: 1.0,
                                    unit: "px",
                                    onDragStart: { recordDragStart(item: item) },
                                    onDragEnd: { recordDragEnd(item: item) }
                                ) {
                                    recordChange(item: item)
                                }

                                ScrubbableNumberField(
                                    label: "Pos Y",
                                    value: Binding(
                                        get: { item.pixelY },
                                        set: { item.pixelY = $0 }
                                    ),
                                    range: -1080...2160,
                                    step: 1.0,
                                    unit: "px",
                                    onDragStart: { recordDragStart(item: item) },
                                    onDragEnd: { recordDragEnd(item: item) }
                                ) {
                                    recordChange(item: item)
                                }
                            }

                            HStack(spacing: 4) {
                                ScrubbableNumberField(
                                    label: "Scale X",
                                    value: Binding(
                                        get: { item.scaleXPercent },
                                        set: { item.scaleXPercent = $0 }
                                    ),
                                    range: 1...1000,
                                    step: 1.0,
                                    unit: "%",
                                    onDragStart: { recordDragStart(item: item) },
                                    onDragEnd: { recordDragEnd(item: item) }
                                ) {
                                    recordChange(item: item)
                                }

                                Button {
                                    item.isScaleLocked.toggle()
                                    engine.objectWillChange.send()
                                } label: {
                                    Image(systemName: item.isScaleLocked ? "link" : "link.badge.plus")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(item.isScaleLocked ? .blue : .secondary.opacity(0.6))
                                        .frame(width: 20, height: 20)
                                        .background(
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(item.isScaleLocked ? Color.blue.opacity(0.12) : Color.clear)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 3)
                                                .stroke(item.isScaleLocked ? Color.blue.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                                .help(item.isScaleLocked ? "Uniform Scale: Locked (Aspect ratio linked)" : "Uniform Scale: Unlocked (Adjust X and Y independently)")

                                ScrubbableNumberField(
                                    label: "Scale Y",
                                    value: Binding(
                                        get: { item.scaleYPercent },
                                        set: { item.scaleYPercent = $0 }
                                    ),
                                    range: 1...1000,
                                    step: 1.0,
                                    unit: "%",
                                    onDragStart: { recordDragStart(item: item) },
                                    onDragEnd: { recordDragEnd(item: item) }
                                ) {
                                    recordChange(item: item)
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
                                    unit: "%",
                                    onDragStart: { recordDragStart(item: item) },
                                    onDragEnd: { recordDragEnd(item: item) }
                                ) {
                                    recordChange(item: item)
                                }

                                ScrubbableNumberField(
                                    label: "Right",
                                    value: Binding(
                                        get: { item.cropRightPercent },
                                        set: { item.cropRightPercent = $0 }
                                    ),
                                    range: 0...95,
                                    step: 0.5,
                                    unit: "%",
                                    onDragStart: { recordDragStart(item: item) },
                                    onDragEnd: { recordDragEnd(item: item) }
                                ) {
                                    recordChange(item: item)
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
                                    unit: "%",
                                    onDragStart: { recordDragStart(item: item) },
                                    onDragEnd: { recordDragEnd(item: item) }
                                ) {
                                    recordChange(item: item)
                                }

                                ScrubbableNumberField(
                                    label: "Bottom",
                                    value: Binding(
                                        get: { item.cropBottomPercent },
                                        set: { item.cropBottomPercent = $0 }
                                    ),
                                    range: 0...95,
                                    step: 0.5,
                                    unit: "%",
                                    onDragStart: { recordDragStart(item: item) },
                                    onDragEnd: { recordDragEnd(item: item) }
                                ) {
                                    recordChange(item: item)
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
                                unit: "%",
                                onDragStart: { recordDragStart(item: item) },
                                onDragEnd: { recordDragEnd(item: item) }
                            ) {
                                recordChange(item: item)
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

    private func recordDragStart(item: SceneItem) {
        dragStartSnapshot = SceneItemTransformSnapshot(from: item)
    }

    private func recordDragEnd(item: SceneItem) {
        if let start = dragStartSnapshot {
            let end = SceneItemTransformSnapshot(from: item)
            engine.recordTransformChange(itemId: item.id, before: start, after: end)
            dragStartSnapshot = nil
        }
    }

    private func recordChange(item: SceneItem) {
        engine.updateSceneItems()
    }
}
