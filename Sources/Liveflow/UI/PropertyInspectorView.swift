import SwiftUI
import AppKit

/// AppKit-backed inline text editor with auto-select-all and right-alignment.
/// Enter = apply, Esc = cancel, Click outside / blur = cancel.
public struct InlineScrubEditor: NSViewRepresentable {
    let initialText: String
    let onCommit: (Double) -> Void
    let onCancel: () -> Void

    public func makeCoordinator() -> Coordinator {
        Coordinator(initialText: initialText, onCommit: onCommit, onCancel: onCancel)
    }

    public func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField()
        tf.isBordered = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.alignment = .right
        tf.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        tf.textColor = .controlTextColor
        tf.stringValue = initialText
        tf.delegate = context.coordinator

        DispatchQueue.main.async {
            if let window = tf.window {
                window.makeFirstResponder(tf)
                tf.selectText(nil) // Selects all text automatically
            }
        }
        return tf
    }

    public func updateNSView(_ nsView: NSTextField, context: Context) {}

    public final class Coordinator: NSObject, NSTextFieldDelegate {
        let initialText: String
        let onCommit: (Double) -> Void
        let onCancel: () -> Void
        private var committed = false

        init(initialText: String, onCommit: @escaping (Double) -> Void, onCancel: @escaping () -> Void) {
            self.initialText = initialText
            self.onCommit = onCommit
            self.onCancel = onCancel
        }

        public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Enter pressed -> Apply
                committed = true
                if let val = Double(control.stringValue) {
                    onCommit(val)
                } else {
                    onCancel()
                }
                control.window?.makeFirstResponder(nil)
                return true
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                // Esc pressed -> Cancel
                committed = true
                onCancel()
                control.window?.makeFirstResponder(nil)
                return true
            }
            return false
        }

        public func controlTextDidEndEditing(_ obj: Notification) {
            if !committed {
                // Clicked outside / blurred -> Cancel without applying
                onCancel()
            }
        }
    }
}

/// Premiere Pro-style scrubbable numeric field.
/// Click and drag horizontally to smoothly adjust values with real-time visual feedback.
/// Supports Shift for 5x acceleration, Option for 0.1x precision, and double-click to type directly.
public struct ScrubbableNumberField: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let onDragStart: (() -> Void)?
    let onDragEnd: (() -> Void)?
    let onCommit: () -> Void

    @State private var isHovered = false
    @State private var isDragging = false
    @State private var isEditing = false
    @State private var dragAccumulated: CGFloat = 0

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
                .frame(width: 38, alignment: .leading)

            ZStack(alignment: .trailing) {
                if isEditing {
                    InlineScrubEditor(
                        initialText: String(format: "%.0f", value),
                        onCommit: { newVal in
                            isEditing = false
                            value = min(max(range.lowerBound, newVal), range.upperBound)
                            onCommit()
                        },
                        onCancel: {
                            isEditing = false
                        }
                    )
                    .frame(height: 18)
                    .padding(.horizontal, 4)
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
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(isDragging ? Color.blue.opacity(0.18) : (isHovered || isEditing ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isDragging ? Color.blue : (isHovered || isEditing ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2)), lineWidth: 1)
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
                DragGesture(minimumDistance: 1)
                    .onChanged { gesture in
                        guard !isEditing else { return }
                        if !isDragging {
                            isDragging = true
                            dragAccumulated = 0
                            onDragStart?()
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
                        guard !isEditing else { return }
                        isDragging = false
                        dragAccumulated = 0
                        onDragEnd?()
                    }
            )
            .onTapGesture(count: 2) {
                isEditing = true
            }
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
                                    unit: "px",
                                    onDragStart: { recordDragStart(item: item) },
                                    onDragEnd: { recordDragEnd(item: item) }
                                ) {
                                    recordChange(item: item)
                                }

                                ScrubbableNumberField(
                                    label: "Y",
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

                            HStack(spacing: 8) {
                                ScrubbableNumberField(
                                    label: "W",
                                    value: Binding(
                                        get: { item.pixelWidth },
                                        set: { item.pixelWidth = $0 }
                                    ),
                                    range: 20...3840,
                                    step: 1.0,
                                    unit: "px",
                                    onDragStart: { recordDragStart(item: item) },
                                    onDragEnd: { recordDragEnd(item: item) }
                                ) {
                                    recordChange(item: item)
                                }

                                ScrubbableNumberField(
                                    label: "H",
                                    value: Binding(
                                        get: { item.pixelHeight },
                                        set: { item.pixelHeight = $0 }
                                    ),
                                    range: 20...2160,
                                    step: 1.0,
                                    unit: "px",
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
