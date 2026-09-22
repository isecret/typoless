import AppKit
import Carbon.HIToolbox
import SwiftUI

struct HotkeyRecorderView: View {
    let hotkey: HotkeyCombo
    var onCommit: (HotkeyCombo) -> Bool
    var onPhaseChanged: ((HotkeyRecordingPhase) -> Void)?
    var onRecordingStateChanged: ((Bool) -> Void)?

    @State private var phase: HotkeyRecordingPhase = .idle
    @State private var previewCombo: HotkeyCombo?

    var body: some View {
        HStack(spacing: 8) {
            display
                .frame(minHeight: SettingsFormLayout.rowMinHeight, alignment: .leading)
                .layoutPriority(0)

            Button(phase == .idle ? "更改…" : "取消") {
                if phase == .idle {
                    beginRecording()
                } else {
                    cancelRecording()
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
            .help(phase == .idle ? "更改快捷键" : "取消录制")
        }
        .frame(width: SettingsFormLayout.controlWidth, alignment: .leading)
        .background {
            if phase != .idle {
                HotkeyRecorderCaptureRepresentable(
                    isActive: true,
                    onPreview: { combo in
                        previewCombo = combo
                        updatePhase(combo == nil ? .waiting : .previewingModifiers)
                    },
                    onCommit: commit,
                    onCancel: cancelRecording
                )
            }
        }
        .onDisappear {
            if phase != .idle {
                cancelRecording()
            }
        }
    }

    @ViewBuilder
    private var display: some View {
        switch phase {
        case .idle:
            Button(action: beginRecording) {
                HotkeyTokenCluster(tokens: HotkeyPresentation(combo: hotkey).visualTokens)
            }
            .buttonStyle(.plain)
            .help(HotkeyPresentation(combo: hotkey).accessibilityDescription)
            .accessibilityLabel("当前快捷键")
            .accessibilityValue(HotkeyPresentation(combo: hotkey).accessibilityDescription)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("点按以更改快捷键")
        case .waiting:
            HStack(spacing: 6) {
                Image(systemName: "keyboard")
                    .foregroundStyle(.secondary)
                Text("请按下新的快捷键…")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("请按下新的快捷键")
        case .previewingModifiers:
            if let previewCombo {
                HotkeyTokenCluster(tokens: HotkeyPresentation(combo: previewCombo).visualTokens)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("正在录制的快捷键")
                    .accessibilityValue(HotkeyPresentation(combo: previewCombo).accessibilityDescription)
            }
        }
    }

    private func beginRecording() {
        guard phase == .idle else { return }
        previewCombo = nil
        updatePhase(.waiting)
        onRecordingStateChanged?(true)
    }

    private func cancelRecording() {
        guard phase != .idle else { return }
        previewCombo = nil
        updatePhase(.idle)
        onRecordingStateChanged?(false)
    }

    private func commit(_ combo: HotkeyCombo) {
        let accepted = onCommit(combo)
        previewCombo = nil
        updatePhase(.idle)
        onRecordingStateChanged?(false)
        _ = accepted
    }

    private func updatePhase(_ newPhase: HotkeyRecordingPhase) {
        phase = newPhase
        onPhaseChanged?(newPhase)
    }
}

private struct HotkeyTokenCluster: View {
    let tokens: [HotkeyToken]

    var body: some View {
        HotkeyTokenTruncatingLayout(spacing: 4) {
            ForEach(tokens) { token in
                Text(token.visualLabel)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 6)
                    .frame(minHeight: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
    }
}

private struct HotkeyTokenTruncatingLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 22
        let contentWidth = subviews.reduce(into: CGFloat.zero) { partial, subview in
            let itemWidth = subview.sizeThatFits(.unspecified).width
            partial = partial == 0 ? itemWidth : partial + spacing + itemWidth
        }
        if let proposedWidth = proposal.width {
            return CGSize(width: min(contentWidth, max(0, proposedWidth)), height: height)
        }
        return CGSize(width: contentWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        let maxX = bounds.maxX
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > maxX {
                break
            }
            subview.place(
                at: CGPoint(x: x, y: bounds.midY - size.height / 2),
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
        }
    }
}

private struct HotkeyRecorderCaptureRepresentable: NSViewRepresentable {
    var isActive: Bool
    var onPreview: (HotkeyCombo?) -> Void
    var onCommit: (HotkeyCombo) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> HotkeyRecorderControl {
        let control = HotkeyRecorderControl(frame: .zero)
        control.onPreview = onPreview
        control.onCommit = onCommit
        control.onCancel = onCancel
        control.isActive = isActive
        return control
    }

    func updateNSView(_ nsView: HotkeyRecorderControl, context: Context) {
        nsView.onPreview = onPreview
        nsView.onCommit = onCommit
        nsView.onCancel = onCancel
        nsView.isActive = isActive
    }
}

final class HotkeyRecorderControl: NSView {
    var onPreview: ((HotkeyCombo?) -> Void)?
    var onCommit: ((HotkeyCombo) -> Void)?
    var onCancel: (() -> Void)?

    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            if isActive {
                startSession()
            } else {
                stopSession(notifyCancel: false)
            }
        }
    }

    override var acceptsFirstResponder: Bool { isActive }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private var largestModifierSetSeen: Set<HotkeyPhysicalModifier> = []
    private var currentModifierPreview: Set<HotkeyPhysicalModifier> = []
    private var outsideClickMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: SettingsFormLayout.rowMinHeight)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopSession(notifyCancel: true)
            return
        }
        if isActive {
            window?.makeFirstResponder(self)
            observeWindowResign()
        }
    }

    override func mouseDown(with event: NSEvent) {
        if isActive {
            window?.makeFirstResponder(self)
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard isActive else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            cancel()
            return
        }

        if hasMarkedText {
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
            keyLabel: HotkeyPresentation.keyLabel(from: event),
            physicalModifiers: physicalModifiers.map(\.spec)
        )
        commit(combo)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isActive else {
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
                    modifiers: largestModifierSetSeen.map(\.spec)
                )
                commit(combo)
            } else {
                cancel()
            }
            return
        }

        let preview = HotkeyCombo.special(modifiers: currentModifierPreview.map(\.spec))
        onPreview?(preview)
    }

    private var hasMarkedText: Bool {
        NSTextInputContext.current?.client.hasMarkedText() == true
    }

    private func startSession() {
        largestModifierSetSeen = []
        currentModifierPreview = []
        installOutsideClickMonitor()
        observeWindowResign()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isActive else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    private func cancel() {
        stopSession(notifyCancel: true)
    }

    private func commit(_ combo: HotkeyCombo) {
        onCommit?(combo)
        stopSession(notifyCancel: false)
    }

    private func stopSession(notifyCancel: Bool) {
        largestModifierSetSeen = []
        currentModifierPreview = []
        removeOutsideClickMonitor()
        removeResignObserver()
        if notifyCancel {
            onCancel?()
        }
    }

    private func observeWindowResign() {
        removeResignObserver()
        guard let window else { return }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.cancel()
            }
        }
    }

    private func removeResignObserver() {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self, self.isActive else { return event }
            guard let window = self.window, event.window === window else {
                self.cancel()
                return event
            }

            let location = self.convert(event.locationInWindow, from: nil)
            if let superview = self.superview {
                let locationInRow = superview.convert(event.locationInWindow, from: nil)
                if !superview.bounds.contains(locationInRow) {
                    self.cancel()
                }
            } else if !self.bounds.contains(location) {
                self.cancel()
            }
            return event
        }
    }

    private func removeOutsideClickMonitor() {
        guard let outsideClickMonitor else { return }
        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
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
}
