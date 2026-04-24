import AppKit
import Carbon.HIToolbox
import Foundation

/// 全局快捷键管理器，使用 Carbon Event API 注册和监听全局热键按下/松开
final class HotkeyManager: @unchecked Sendable {

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var isKeyDown = false

    /// 快捷键按下回调
    var onKeyDown: (@MainActor @Sendable () -> Void)?
    /// 快捷键松开回调
    var onKeyUp: (@MainActor @Sendable () -> Void)?

    private static let hotkeySignature: FourCharCode = 0x5459504C // "TYPL"
    private static let hotkeyID: UInt32 = 1

    deinit {
        unregister()
    }

    /// 注册全局快捷键
    func register(hotkey: HotkeyCombo) {
        unregister()

        let carbonMods = Self.carbonModifiers(from: hotkey.modifiers)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        var eventTypes = [
            EventTypeSpec(
                eventClass: UInt32(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: UInt32(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            ),
        ]

        InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotkeyCallback,
            2,
            &eventTypes,
            selfPtr,
            &eventHandlerRef
        )

        let hotKeyID = EventHotKeyID(
            signature: Self.hotkeySignature,
            id: Self.hotkeyID
        )

        RegisterEventHotKey(
            UInt32(hotkey.keyCode),
            carbonMods,
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(0),
            &hotKeyRef
        )
    }

    /// 注销当前注册的快捷键
    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
        isKeyDown = false
    }

    // MARK: - Carbon Event Handling

    fileprivate func handlePress() {
        guard !isKeyDown else { return }
        isKeyDown = true
        if let callback = onKeyDown {
            Task { @MainActor in callback() }
        }
    }

    fileprivate func handleRelease() {
        guard isKeyDown else { return }
        isKeyDown = false
        if let callback = onKeyUp {
            Task { @MainActor in callback() }
        }
    }

    // MARK: - Modifier Conversion

    private static func carbonModifiers(from nsModifiers: UInt) -> UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: nsModifiers)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }
}

// MARK: - Carbon Callback

private func carbonHotkeyCallback(
    _: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

    switch GetEventKind(event) {
    case UInt32(kEventHotKeyPressed):
        manager.handlePress()
    case UInt32(kEventHotKeyReleased):
        manager.handleRelease()
    default:
        return OSStatus(eventNotHandledErr)
    }

    return noErr
}
