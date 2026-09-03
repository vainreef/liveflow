import SwiftUI
import AppKit

/// High-performance AppKit scrubbable numeric field.
/// - Single click: Instantly focuses, selects all text, right-aligned, ready to type.
/// - Click & drag: Smooth horizontal scrub with Shift (5x) and Option (0.1x).
/// - Enter: Commits new value.
/// - Esc / Click outside: Cancels without applying, reverts cleanly.
public final class ScrubbableNumberNSView: NSView, NSTextFieldDelegate {
    public var labelText: String = "" {
        didSet { labelField.stringValue = labelText }
    }
    public var value: Double = 0.0 {
        didSet {
            if !isEditing {
                updateDisplay()
            }
        }
    }
    public var range: ClosedRange<Double> = 0...100
    public var step: Double = 1.0
    public var unit: String = ""
    public var onDragStart: (() -> Void)?
    public var onDragEnd: (() -> Void)?
    public var onCommit: ((Double) -> Void)?

    private let labelField = NSTextField(labelWithString: "")
    private let valueContainer = NSView()
    private let displayField = NSTextField(labelWithString: "")
    private let editField = NSTextField()

    public private(set) var isEditing: Bool = false
    private var isDragging: Bool = false
    private var mouseDownPos: NSPoint = .zero
    private var originalVal: Double = 0.0
    private var committed: Bool = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true

        // 1. Label
        labelField.font = .systemFont(ofSize: 10, weight: .bold)
        labelField.textColor = .secondaryLabelColor
        labelField.alignment = .left
        labelField.lineBreakMode = .byTruncatingTail
        addSubview(labelField)

        // 2. Value container box
        valueContainer.wantsLayer = true
        valueContainer.layer?.cornerRadius = 3.0
        valueContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        valueContainer.layer?.borderWidth = 1.0
        valueContainer.layer?.borderColor = NSColor.separatorColor.cgColor
        addSubview(valueContainer)

        // 3. Display Field
        displayField.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        displayField.textColor = .controlTextColor
        displayField.alignment = .right
        displayField.isBordered = false
        displayField.drawsBackground = false
        valueContainer.addSubview(displayField)

        // 4. Edit Field
        editField.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        editField.textColor = .controlTextColor
        editField.alignment = .right
        editField.isBordered = false
        editField.drawsBackground = false
        editField.focusRingType = .none
        editField.delegate = self
        editField.isHidden = true
        valueContainer.addSubview(editField)
    }

    public override func layout() {
        super.layout()
        let labelW: CGFloat = 44.0
        let h = bounds.height
        labelField.frame = NSRect(x: 0, y: (h - 14) / 2.0, width: labelW, height: 14)

        let valX = labelW + 2
        let valW = max(20, bounds.width - valX)
        valueContainer.frame = NSRect(x: valX, y: 0, width: valW, height: h)

        let innerBounds = NSRect(x: 4, y: 1, width: valW - 8, height: h - 2)
        displayField.frame = innerBounds
        editField.frame = innerBounds
    }

    private func updateDisplay() {
        let formatted = String(format: "%.0f", value)
        if unit.isEmpty {
            displayField.stringValue = formatted
        } else {
            displayField.stringValue = "\(formatted) \(unit)"
        }
    }

    public override func resetCursorRects() {
        if !isEditing {
            addCursorRect(valueContainer.frame, cursor: .resizeLeftRight)
        }
    }

    public override func mouseDown(with event: NSEvent) {
        let pointInContainer = valueContainer.convert(event.locationInWindow, from: nil)
        if valueContainer.bounds.contains(pointInContainer) && !isEditing {
            mouseDownPos = event.locationInWindow
            isDragging = false
        } else {
            super.mouseDown(with: event)
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        guard !isEditing else { return }
        let currentPos = event.locationInWindow
        let totalDx = currentPos.x - mouseDownPos.x

        if !isDragging && abs(totalDx) >= 3.0 {
            isDragging = true
            onDragStart?()
            valueContainer.layer?.borderColor = NSColor.systemBlue.cgColor
            valueContainer.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.15).cgColor
        }

        if isDragging {
            var mult = 1.0
            if event.modifierFlags.contains(.shift) {
                mult = 5.0
            } else if event.modifierFlags.contains(.option) {
                mult = 0.1
            }
            let delta = Double(event.deltaX) * step * mult
            let newVal = min(max(range.lowerBound, value + delta), range.upperBound)
            if newVal != value {
                value = newVal
                updateDisplay()
                onCommit?(newVal)
            }
        }
    }

    public override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            valueContainer.layer?.borderColor = NSColor.separatorColor.cgColor
            valueContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            onDragEnd?()
        } else {
            let pointInContainer = valueContainer.convert(event.locationInWindow, from: nil)
            if valueContainer.bounds.contains(pointInContainer) && !isEditing {
                // SINGLE CLICK -> INITIATE EDITING!
                startEditing()
            }
        }
    }

    private func startEditing() {
        isEditing = true
        committed = false
        originalVal = value

        displayField.isHidden = true
        editField.isHidden = false
        editField.stringValue = String(format: "%.0f", value)

        valueContainer.layer?.borderColor = NSColor.controlAccentColor.cgColor
        valueContainer.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor

        window?.makeFirstResponder(editField)
        editField.selectText(nil) // Fully selects all text on click
        window?.invalidateCursorRects(for: self)
    }

    private func stopEditing(apply: Bool) {
        guard isEditing else { return }
        isEditing = false

        if apply {
            if let val = Double(editField.stringValue) {
                let clamped = min(max(range.lowerBound, val), range.upperBound)
                value = clamped
                onCommit?(clamped)
            }
        } else {
            value = originalVal
        }

        updateDisplay()
        editField.isHidden = true
        displayField.isHidden = false

        valueContainer.layer?.borderColor = NSColor.separatorColor.cgColor
        valueContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        window?.invalidateCursorRects(for: self)
    }

    // MARK: - NSTextFieldDelegate
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // Enter key pressed -> Apply
            committed = true
            stopEditing(apply: true)
            window?.makeFirstResponder(nil)
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            // Escape key pressed -> Cancel
            committed = true
            stopEditing(apply: false)
            window?.makeFirstResponder(nil)
            return true
        }
        return false
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        if !committed {
            // Lost focus / click outside -> Cancel without applying
            stopEditing(apply: false)
        }
    }
}

/// SwiftUI wrapper for ScrubbableNumberNSView
public struct ScrubbableNumberField: NSViewRepresentable {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let onDragStart: (() -> Void)?
    let onDragEnd: (() -> Void)?
    let onCommit: () -> Void

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

    public func makeNSView(context: Context) -> ScrubbableNumberNSView {
        let view = ScrubbableNumberNSView()
        view.labelText = label
        view.value = value
        view.range = range
        view.step = step
        view.unit = unit
        view.onDragStart = onDragStart
        view.onDragEnd = onDragEnd
        view.onCommit = { newVal in
            self.value = newVal
            self.onCommit()
        }
        return view
    }

    public func updateNSView(_ nsView: ScrubbableNumberNSView, context: Context) {
        nsView.labelText = label
        nsView.range = range
        nsView.step = step
        nsView.unit = unit
        nsView.onDragStart = onDragStart
        nsView.onDragEnd = onDragEnd
        nsView.onCommit = { newVal in
            self.value = newVal
            self.onCommit()
        }
        if !nsView.isEditing {
            nsView.value = value
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
                                .frame(height: 20)

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
                                .frame(height: 20)
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
                                .frame(height: 20)

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
                                .frame(height: 20)
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
                                .frame(height: 20)

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
                                .frame(height: 20)
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
                                .frame(height: 20)

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
                                .frame(height: 20)
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
                            .frame(height: 20)
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
