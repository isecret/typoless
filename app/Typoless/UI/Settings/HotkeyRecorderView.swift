import AppKit
import Carbon.HIToolbox
import SwiftUI

struct HotkeyRecorderView: View {
    @Binding var hotkey: HotkeyCombo
    var onRecordingStateChanged: ((Bool) -> Void)?

    var body: some View {
        HotkeyRecorderFieldRepresentable(
            hotkey: $hotkey,
            onRecordingStateChanged: onRecordingStateChanged
        )
    }
}

private struct HotkeyRecorderFieldRepresentable: NSViewRepresentable {
    @Binding var hotkey: HotkeyCombo
    var onRecordingStateChanged: ((Bool) -> Void)?

    func makeNSView(context: Context) -> HotkeyRecorderControl {
        let control = HotkeyRecorderControl(frame: .zero)
        control.onHotkeyChange = { newHotkey in
            hotkey = newHotkey
        }
        control.onRecordingStateChange = { isRecording in
            onRecordingStateChanged?(isRecording)
        }
        control.hotkey = hotkey
        return control
    }

    func updateNSView(_ nsView: HotkeyRecorderControl, context: Context) {
        nsView.onRecordingStateChange = { isRecording in
            onRecordingStateChanged?(isRecording)
        }
        nsView.hotkey = hotkey
    }
}

private final class PaddedHotkeyRecorderCell: NSTextFieldCell {
    private let horizontalPadding: CGFloat = 7

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        super.drawingRect(forBounds: insetBounds(rect))
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        super.titleRect(forBounds: insetBounds(rect))
    }

    override func cellSize(forBounds rect: NSRect) -> NSSize {
        let size = super.cellSize(forBounds: rect)
        return NSSize(width: size.width + (horizontalPadding * 2), height: size.height)
    }

    private func insetBounds(_ rect: NSRect) -> NSRect {
        NSRect(
            x: rect.origin.x + horizontalPadding,
            y: rect.origin.y,
            width: max(0, rect.size.width - (horizontalPadding * 2)),
            height: rect.size.height
        )
    }
}

final class HotkeyRecorderControl: NSTextField {
    private enum Layout {
        static let minWidth: CGFloat = 92
        static let maxWidth: CGFloat = 240
        static let fallbackHorizontalPadding: CGFloat = 18
        static let cornerRadius: CGFloat = 6
        static let idleBorderWidth: CGFloat = 1
        static let recordingBorderWidth: CGFloat = 2
    }

    var hotkey: HotkeyCombo = .default {
        didSet {
            guard !isRecording else { return }
            refreshLabel()
        }
    }

    var onHotkeyChange: ((HotkeyCombo) -> Void)?
    var onRecordingStateChange: ((Bool) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        let nativeWidth = super.intrinsicContentSize.width
        let fallbackWidth = measuredTextWidth(for: stringValue) + Layout.fallbackHorizontalPadding
        let width = min(
            Layout.maxWidth,
            max(Layout.minWidth, max(nativeWidth, fallbackWidth))
        )
        return NSSize(width: width, height: SettingsFormLayout.rowMinHeight)
    }

    private var isRecording = false
    private var largestModifierSetSeen: Set<HotkeyPhysicalModifier> = []
    private var currentModifierPreview: Set<HotkeyPhysicalModifier> = []
    private var outsideClickMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            removeOutsideClickMonitor()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        beginRecording()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            cancelRecording()
            return
        }

        guard !HotkeyPhysicalModifier.modifierKeyCodes.contains(UInt16(event.keyCode)) else {
            return
        }

        let genericModifiers = HotkeyPhysicalModifier.pressedSet(from: event.modifierFlags).genericFlags
        let physicalModifiers = HotkeyPhysicalModifier.pressedSet(from: event.modifierFlags)
        let combo = HotkeyCombo.standard(
            keyCode: UInt16(event.keyCode),
            modifiers: genericModifiers.rawValue,
            keyLabel: Self.keyLabel(from: event),
            physicalModifiers: physicalModifiers.map(\.spec)
        )
        commit(combo)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }

        let pressed = HotkeyPhysicalModifier.pressedSet(from: event.modifierFlags)
        let resolvedState = Self.resolveModifierPreviewState(
            pressed: pressed,
            previousLargest: largestModifierSetSeen
        )
        currentModifierPreview = resolvedState.preview
        largestModifierSetSeen = resolvedState.largest

        if pressed.isEmpty {
            if !largestModifierSetSeen.isEmpty {
                let combo = HotkeyCombo.special(
                    modifiers: largestModifierSetSeen
                        .map(\.spec)
                )
                commit(combo)
            } else {
                cancelRecording()
            }
            return
        }

        refreshLabel()
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if isRecording {
            cancelRecording()
        }
        return result
    }

    private func setupView() {
        cell = PaddedHotkeyRecorderCell(textCell: "")
        isEditable = false
        isSelectable = false
        isBordered = true
        isBezeled = true
        bezelStyle = .roundedBezel
        controlSize = .regular
        focusRingType = .default
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        lineBreakMode = .byTruncatingTail
        maximumNumberOfLines = 1
        alignment = .center
        font = .systemFont(ofSize: NSFont.systemFontSize)
        textColor = .labelColor
        wantsLayer = true
        layer?.cornerRadius = Layout.cornerRadius

        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: SettingsFormLayout.rowMinHeight).isActive = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        refreshAppearance()
        refreshLabel()
    }

    private func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        largestModifierSetSeen = []
        currentModifierPreview = []
        installOutsideClickMonitor()
        onRecordingStateChange?(true)
        refreshAppearance()
        refreshLabel()
    }

    private func cancelRecording() {
        endRecordingSession()
    }

    private func commit(_ newHotkey: HotkeyCombo) {
        hotkey = newHotkey
        onHotkeyChange?(newHotkey)
        endRecordingSession()
    }

    private func refreshAppearance() {
        textColor = isRecording ? .secondaryLabelColor : .labelColor
        layer?.borderWidth = isRecording ? Layout.recordingBorderWidth : Layout.idleBorderWidth
        layer?.borderColor = isRecording
            ? NSColor.controlAccentColor.cgColor
            : NSColor.quaternaryLabelColor.cgColor
    }

    private func endRecordingSession() {
        guard isRecording else { return }
        isRecording = false
        largestModifierSetSeen = []
        currentModifierPreview = []
        removeOutsideClickMonitor()
        onRecordingStateChange?(false)
        refreshAppearance()
        refreshLabel()
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self, self.isRecording else { return event }
            guard let window = self.window, event.window === window else {
                self.cancelRecording()
                return event
            }

            let location = self.convert(event.locationInWindow, from: nil)
            if !self.bounds.contains(location) {
                self.cancelRecording()
            }
            return event
        }
    }

    private func removeOutsideClickMonitor() {
        guard let outsideClickMonitor else { return }
        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }

    private func refreshLabel() {
        if isRecording {
            if currentModifierPreview.isEmpty {
                stringValue = "按下快捷键"
            } else {
                let preview = HotkeyCombo.special(modifiers: currentModifierPreview.map(\.spec))
                stringValue = preview.displayString
            }
            invalidateIntrinsicContentSize()
            return
        }

        stringValue = hotkey.displayString
        invalidateIntrinsicContentSize()
    }

    private func measuredTextWidth(for text: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? .systemFont(ofSize: NSFont.systemFontSize)
        ]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }

    static func resolveModifierPreviewState(
        pressed: Set<HotkeyPhysicalModifier>,
        previousLargest: Set<HotkeyPhysicalModifier>
    ) -> (preview: Set<HotkeyPhysicalModifier>, largest: Set<HotkeyPhysicalModifier>) {
        let largest: Set<HotkeyPhysicalModifier>
        if pressed.count >= previousLargest.count {
            largest = pressed
        } else {
            largest = previousLargest
        }

        let preview: Set<HotkeyPhysicalModifier>
        if pressed.isEmpty {
            preview = largest
        } else if largest.isSuperset(of: pressed) {
            preview = largest
        } else {
            preview = pressed
        }

        return (preview, largest)
    }

    private static func keyLabel(from event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space:
            return "Space"
        case kVK_Tab:
            return "Tab"
        case kVK_Return:
            return "Return"
        case kVK_Escape:
            return "Esc"
        case kVK_Delete:
            return "Delete"
        case kVK_ForwardDelete:
            return "Forward Delete"
        case kVK_LeftArrow:
            return "Left Arrow"
        case kVK_RightArrow:
            return "Right Arrow"
        case kVK_UpArrow:
            return "Up Arrow"
        case kVK_DownArrow:
            return "Down Arrow"
        default:
            if let characters = event.charactersIgnoringModifiers?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !characters.isEmpty {
                return characters.uppercased()
            }
            return "Key \(event.keyCode)"
        }
    }
}
