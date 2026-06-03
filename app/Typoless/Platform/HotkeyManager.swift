import AppKit
import Carbon.HIToolbox
import Foundation

/// 全局快捷键管理器，使用 Carbon Event API 注册和监听全局热键按下/松开
final class HotkeyManager: @unchecked Sendable {

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var isKeyDown = false
    private var registeredHotkey: HotkeyCombo?
    private var isSuspended = false

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
        registeredHotkey = hotkey

        if hotkey.isPureModifier {
            registerSpecialHotkey(hotkey)
            return
        }

        if hotkey.hasPhysicalStandardModifiers {
            registerPhysicalStandardHotkey(hotkey)
            return
        }

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
            UInt32(hotkey.keyCode ?? 0),
            carbonMods,
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(0),
            &hotKeyRef
        )
    }

    /// 注销当前注册的快捷键
    func unregister() {
        registeredHotkey = nil
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
        if let monitor = globalFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            globalFlagsMonitor = nil
        }
        if let monitor = localFlagsMonitor {
            NSEvent.removeMonitor(monitor)
            localFlagsMonitor = nil
        }
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        isKeyDown = false
    }

    func setSuspended(_ suspended: Bool) {
        isSuspended = suspended
        if suspended {
            isKeyDown = false
        }
    }

    // MARK: - Carbon Event Handling

    fileprivate func handlePress() {
        guard !isSuspended else { return }
        guard !isKeyDown else { return }
        isKeyDown = true
        if let callback = onKeyDown {
            Task { @MainActor in callback() }
        }
    }

    fileprivate func handleRelease() {
        guard !isSuspended else {
            isKeyDown = false
            return
        }
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

    private func registerSpecialHotkey(_ hotkey: HotkeyCombo) {
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleSpecialFlagsChanged(event, hotkey: hotkey)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleSpecialFlagsChanged(event, hotkey: hotkey)
            return event
        }
    }

    private func registerPhysicalStandardHotkey(_ hotkey: HotkeyCombo) {
        let keyMask: NSEvent.EventTypeMask = [.keyDown, .keyUp]
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: keyMask) { [weak self] event in
            self?.handlePhysicalStandardEvent(event, hotkey: hotkey)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: keyMask) { [weak self] event in
            self?.handlePhysicalStandardEvent(event, hotkey: hotkey)
            return event
        }
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handlePhysicalStandardEvent(event, hotkey: hotkey)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handlePhysicalStandardEvent(event, hotkey: hotkey)
            return event
        }
    }

    private func handleSpecialFlagsChanged(_ event: NSEvent, hotkey: HotkeyCombo) {
        let pressed = HotkeyPhysicalModifier.pressedSet(from: event.modifierFlags)
        if hotkey.matchesSpecialPressedModifiers(pressed) {
            handlePress()
        } else {
            handleRelease()
        }
    }

    private func handlePhysicalStandardEvent(_ event: NSEvent, hotkey: HotkeyCombo) {
        let pressed = HotkeyPhysicalModifier.pressedSet(from: event.modifierFlags)

        switch event.type {
        case .keyDown:
            if hotkey.matchesStandardPressedModifiers(
                keyCode: UInt16(event.keyCode),
                pressed: pressed
            ) {
                handlePress()
            }
        case .keyUp:
            if hotkey.keyCode == UInt16(event.keyCode) {
                handleRelease()
            }
        case .flagsChanged:
            guard isKeyDown, let keyCode = hotkey.keyCode else { return }
            if !hotkey.matchesStandardPressedModifiers(keyCode: keyCode, pressed: pressed) {
                handleRelease()
            }
        default:
            return
        }
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
