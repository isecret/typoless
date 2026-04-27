import KeyboardShortcuts
import SwiftUI

/// 快捷键录制控件：使用 KeyboardShortcuts.Recorder 替代手工 NSView 方案，
/// 解决焦点管理问题。仅用于录制 UI，全局快捷键注册由 HotkeyManager 负责。
struct HotkeyRecorderView: View {
    @Binding var hotkey: HotkeyCombo

    var body: some View {
        KeyboardShortcuts.Recorder(for: .toggleHotkey) { newShortcut in
            // 立即解除 KeyboardShortcuts 的全局注册，避免与 HotkeyManager 冲突
            KeyboardShortcuts.disable(.toggleHotkey)
            if let newShortcut {
                hotkey = HotkeyCombo(from: newShortcut)
            }
        }
        .onAppear {
            // 将 ConfigStore 中的当前值同步到 Recorder 用于显示
            KeyboardShortcuts.setShortcut(hotkey.asKeyboardShortcut, for: .toggleHotkey)
            KeyboardShortcuts.disable(.toggleHotkey)
        }
    }
}
