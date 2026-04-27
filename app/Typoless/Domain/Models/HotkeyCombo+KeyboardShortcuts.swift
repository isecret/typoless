import AppKit
import KeyboardShortcuts

extension HotkeyCombo {
    /// Convert to KeyboardShortcuts.Shortcut for the binding-based Recorder UI.
    var asKeyboardShortcut: KeyboardShortcuts.Shortcut {
        KeyboardShortcuts.Shortcut(
            KeyboardShortcuts.Key(rawValue: Int(keyCode)),
            modifiers: NSEvent.ModifierFlags(rawValue: modifiers)
        )
    }

    /// Create from a KeyboardShortcuts.Shortcut recorded by the Recorder UI.
    /// Must be called on MainActor because Shortcut.description uses TIS APIs.
    @MainActor
    init(from shortcut: KeyboardShortcuts.Shortcut) {
        self.init(
            keyCode: UInt16(shortcut.carbonKeyCode),
            modifiers: shortcut.modifiers.rawValue,
            displayString: shortcut.description
        )
    }
}
