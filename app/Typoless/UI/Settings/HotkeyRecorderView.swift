import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 快捷键录制控件：点击后监听下一个键盘组合
struct HotkeyRecorderView: View {
    @Binding var hotkey: HotkeyCombo
    @Binding var isRecording: Bool

    var body: some View {
        Button {
            isRecording.toggle()
        } label: {
            Text(isRecording ? "请按下快捷键…" : hotkey.displayString)
                .frame(minWidth: 120)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
        }
        .background(
            HotkeyRecorderEventView(hotkey: $hotkey, isRecording: $isRecording)
        )
    }
}

// MARK: - NSView 封装用于捕获键盘事件

private struct HotkeyRecorderEventView: NSViewRepresentable {
    @Binding var hotkey: HotkeyCombo
    @Binding var isRecording: Bool

    func makeNSView(context: Context) -> HotkeyNSView {
        let view = HotkeyNSView()
        view.onKeyDown = { [self] event in
            guard isRecording else { return }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !mods.isEmpty else { return }
            let display = Self.displayString(keyCode: event.keyCode, modifiers: mods)
            hotkey = HotkeyCombo(
                keyCode: event.keyCode,
                modifiers: mods.rawValue,
                displayString: display
            )
            isRecording = false
        }
        return view
    }

    func updateNSView(_ nsView: HotkeyNSView, context: Context) {
        nsView.shouldCapture = isRecording
    }

    static func displayString(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }

        let keyName = keyCodeName(keyCode)
        parts.append(keyName)
        return parts.joined(separator: " ")
    }

    // 常用键码映射（避免 Carbon TIS 依赖）
    static func keyCodeName(_ keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Space: "Space"
        case kVK_Return: "Return"
        case kVK_Tab: "Tab"
        case kVK_Delete: "Delete"
        case kVK_Escape: "Escape"
        case kVK_LeftArrow: "←"
        case kVK_RightArrow: "→"
        case kVK_DownArrow: "↓"
        case kVK_UpArrow: "↑"
        case kVK_F1: "F1"
        case kVK_F2: "F2"
        case kVK_F3: "F3"
        case kVK_F4: "F4"
        case kVK_F5: "F5"
        case kVK_F6: "F6"
        case kVK_F7: "F7"
        case kVK_F8: "F8"
        case kVK_F9: "F9"
        case kVK_F10: "F10"
        case kVK_F11: "F11"
        case kVK_F12: "F12"
        case kVK_ANSI_A: "A"
        case kVK_ANSI_S: "S"
        case kVK_ANSI_D: "D"
        case kVK_ANSI_F: "F"
        case kVK_ANSI_G: "G"
        case kVK_ANSI_H: "H"
        case kVK_ANSI_J: "J"
        case kVK_ANSI_K: "K"
        case kVK_ANSI_L: "L"
        case kVK_ANSI_Q: "Q"
        case kVK_ANSI_W: "W"
        case kVK_ANSI_E: "E"
        case kVK_ANSI_R: "R"
        case kVK_ANSI_T: "T"
        case kVK_ANSI_Y: "Y"
        case kVK_ANSI_U: "U"
        case kVK_ANSI_I: "I"
        case kVK_ANSI_O: "O"
        case kVK_ANSI_P: "P"
        case kVK_ANSI_Z: "Z"
        case kVK_ANSI_X: "X"
        case kVK_ANSI_C: "C"
        case kVK_ANSI_V: "V"
        case kVK_ANSI_B: "B"
        case kVK_ANSI_N: "N"
        case kVK_ANSI_M: "M"
        case kVK_ANSI_0: "0"
        case kVK_ANSI_1: "1"
        case kVK_ANSI_2: "2"
        case kVK_ANSI_3: "3"
        case kVK_ANSI_4: "4"
        case kVK_ANSI_5: "5"
        case kVK_ANSI_6: "6"
        case kVK_ANSI_7: "7"
        case kVK_ANSI_8: "8"
        case kVK_ANSI_9: "9"
        default: "Key(\(keyCode))"
        }
    }
}

final class HotkeyNSView: NSView {
    var onKeyDown: ((NSEvent) -> Void)?
    var shouldCapture = false

    override var acceptsFirstResponder: Bool { shouldCapture }

    override func keyDown(with event: NSEvent) {
        if shouldCapture {
            onKeyDown?(event)
        } else {
            super.keyDown(with: event)
        }
    }
}
