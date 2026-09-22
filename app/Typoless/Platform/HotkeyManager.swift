import AppKit
import Carbon.HIToolbox
import Foundation

enum SpecialHotkeyGestureState: Equatable {
    case idle
    case armed
    case cancelled
}

enum SpecialHotkeyGestureEvent: Equatable {
    case modifierFlagsChanged(Set<HotkeyPhysicalModifier>)
    case keyDown(UInt16)
    case systemDefined
}

enum SpecialHotkeyGestureAction: Equatable, Sendable {
    case none
    case began
    case confirmed
    case cancelled
}

struct SpecialHotkeyTransition: Equatable {
    let state: SpecialHotkeyGestureState
    let action: SpecialHotkeyGestureAction

    var shouldTrigger: Bool {
        action == .confirmed
    }

    init(state: SpecialHotkeyGestureState, action: SpecialHotkeyGestureAction) {
        self.state = state
        self.action = action
    }

    init(state: SpecialHotkeyGestureState, shouldTrigger: Bool) {
        self.init(state: state, action: shouldTrigger ? .confirmed : .none)
    }
}

enum HotkeyRegistrationResult: Equatable {
    case success
    case failure(String)

    var errorMessage: String? {
        switch self {
        case .success:
            nil
        case .failure(let message):
            message
        }
    }
}

/// 全局快捷键管理器，使用 Carbon Event API 注册和监听全局热键按下/松开
final class HotkeyManager: @unchecked Sendable {

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var isKeyDown = false
    private var specialHotkeyGestureState: SpecialHotkeyGestureState = .idle
    private(set) var registeredHotkey: HotkeyCombo?
    private var isSuspended = false
    var testInstallHandler: ((HotkeyCombo) -> HotkeyRegistrationResult)?

    /// 快捷键按下回调
    var onKeyDown: (@MainActor @Sendable () -> Void)?
    /// 快捷键松开回调
    var onKeyUp: (@MainActor @Sendable () -> Void)?
    /// 纯修饰键手势阶段回调：按下候选、干净释放确认或组合键取消
    var onSpecialGestureAction: (@MainActor @Sendable (SpecialHotkeyGestureAction) -> Void)?

    private static let hotkeySignature: FourCharCode = 0x5459504C // "TYPL"
    private static let hotkeyID: UInt32 = 1

    deinit {
        unregister()
    }

    /// 注册全局快捷键。失败时当前没有任何已注册快捷键。
    @discardableResult
    func register(hotkey: HotkeyCombo) -> HotkeyRegistrationResult {
        unregister()
        let result = install(hotkey)
        if case .success = result {
            registeredHotkey = hotkey
        }
        return result
    }

    /// 尝试切换到新快捷键；失败时恢复原来的监听。
    @discardableResult
    func replace(with newHotkey: HotkeyCombo) -> HotkeyRegistrationResult {
        let previous = registeredHotkey
        let result = register(hotkey: newHotkey)
        if case .failure = result, let previous {
            _ = register(hotkey: previous)
        }
        return result
    }

    private func install(_ hotkey: HotkeyCombo) -> HotkeyRegistrationResult {
        if let testInstallHandler {
            return testInstallHandler(hotkey)
        }

        if hotkey.isPureModifier {
            return installSpecialHotkey(hotkey)
        }

        if hotkey.hasPhysicalStandardModifiers {
            return installPhysicalStandardHotkey(hotkey)
        }

        return installCarbonHotkey(hotkey)
    }

    private func installCarbonHotkey(_ hotkey: HotkeyCombo) -> HotkeyRegistrationResult {
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

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotkeyCallback,
            2,
            &eventTypes,
            selfPtr,
            &eventHandlerRef
        )
        guard handlerStatus == noErr else {
            eventHandlerRef = nil
            return .failure("无法注册该快捷键，可能已被系统占用。")
        }

        let hotKeyID = EventHotKeyID(
            signature: Self.hotkeySignature,
            id: Self.hotkeyID
        )
        let registerStatus = RegisterEventHotKey(
            UInt32(hotkey.keyCode ?? 0),
            carbonMods,
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(0),
            &hotKeyRef
        )
        guard registerStatus == noErr, hotKeyRef != nil else {
            if let ref = eventHandlerRef {
                RemoveEventHandler(ref)
                eventHandlerRef = nil
            }
            hotKeyRef = nil
            return .failure("无法注册该快捷键，可能已被系统占用。")
        }

        return .success
    }

    private func installSpecialHotkey(_ hotkey: HotkeyCombo) -> HotkeyRegistrationResult {
        let keyActivityMask: NSEvent.EventTypeMask = [.keyDown, .systemDefined]
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: keyActivityMask) { [weak self] event in
            self?.handleSpecialEvent(event, hotkey: hotkey)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: keyActivityMask) { [weak self] event in
            self?.handleSpecialEvent(event, hotkey: hotkey)
            return event
        }
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleSpecialEvent(event, hotkey: hotkey)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleSpecialEvent(event, hotkey: hotkey)
            return event
        }
        guard globalKeyMonitor != nil, localKeyMonitor != nil,
              globalFlagsMonitor != nil, localFlagsMonitor != nil else {
            unregister()
            return .failure("无法监听该修饰键组合。")
        }
        return .success
    }

    private func installPhysicalStandardHotkey(_ hotkey: HotkeyCombo) -> HotkeyRegistrationResult {
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
        guard globalKeyMonitor != nil, localKeyMonitor != nil,
              globalFlagsMonitor != nil, localFlagsMonitor != nil else {
            unregister()
            return .failure("无法监听该快捷键组合，请检查辅助功能权限。")
        }
        return .success
    }

    /// 注销当前注册的快捷键
    func unregister() {
        cancelPendingSpecialGesture()
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
            cancelPendingSpecialGesture()
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

    private func handleSpecialEvent(_ event: NSEvent, hotkey: HotkeyCombo) {
        let gestureEvent: SpecialHotkeyGestureEvent
        switch event.type {
        case .flagsChanged:
            gestureEvent = .modifierFlagsChanged(
                HotkeyPhysicalModifier.pressedSet(from: event.modifierFlags)
            )
        case .keyDown:
            gestureEvent = .keyDown(UInt16(event.keyCode))
        case .systemDefined:
            gestureEvent = .systemDefined
        default:
            return
        }

        consumeSpecialGestureEvent(gestureEvent, hotkey: hotkey)
    }

    @discardableResult
    func consumeSpecialGestureEvent(
        _ gestureEvent: SpecialHotkeyGestureEvent,
        hotkey: HotkeyCombo
    ) -> Bool {
        let transition = Self.resolveSpecialGestureEvent(
            gestureEvent,
            hotkey: hotkey,
            state: specialHotkeyGestureState,
            isSuspended: isSuspended
        )
        specialHotkeyGestureState = transition.state

        publishSpecialGestureAction(transition.action)

        return transition.shouldTrigger
    }

    /// 纯修饰键按下时进入候选态；未参与其他组合键的完整释放才确认触发。
    static func resolveSpecialGestureEvent(
        _ event: SpecialHotkeyGestureEvent,
        hotkey: HotkeyCombo,
        state: SpecialHotkeyGestureState,
        isSuspended: Bool
    ) -> SpecialHotkeyTransition {
        guard !isSuspended else {
            return SpecialHotkeyTransition(
                state: .idle,
                action: state == .idle ? .none : .cancelled
            )
        }

        switch (state, event) {
        case (.idle, .modifierFlagsChanged(let pressed))
            where hotkey.matchesSpecialPressedModifiers(pressed):
            return SpecialHotkeyTransition(state: .armed, action: .began)
        case (.idle, .modifierFlagsChanged(let pressed))
            where hotkey.pressedModifiersAreSubsetOfRecordedSpecialModifiers(pressed):
            return SpecialHotkeyTransition(state: .idle, shouldTrigger: false)
        case (.idle, .modifierFlagsChanged):
            return SpecialHotkeyTransition(state: .cancelled, shouldTrigger: false)
        case (.armed, .keyDown(let keyCode))
            where !HotkeyPhysicalModifier.modifierKeyCodes.contains(keyCode):
            return SpecialHotkeyTransition(state: .cancelled, shouldTrigger: false)
        case (.armed, .systemDefined):
            return SpecialHotkeyTransition(state: .cancelled, shouldTrigger: false)
        case (.armed, .modifierFlagsChanged(let pressed)) where pressed.isEmpty:
            return SpecialHotkeyTransition(state: .idle, action: .confirmed)
        case (.armed, .modifierFlagsChanged(let pressed))
            where hotkey.matchesSpecialPressedModifiers(pressed)
                || hotkey.pressedModifiersAreSubsetOfRecordedSpecialModifiers(pressed):
            return SpecialHotkeyTransition(state: .armed, shouldTrigger: false)
        case (.armed, .modifierFlagsChanged):
            return SpecialHotkeyTransition(state: .cancelled, shouldTrigger: false)
        case (.cancelled, .modifierFlagsChanged(let pressed)) where pressed.isEmpty:
            return SpecialHotkeyTransition(state: .idle, action: .cancelled)
        default:
            return SpecialHotkeyTransition(state: state, shouldTrigger: false)
        }
    }

    private func cancelPendingSpecialGesture() {
        guard specialHotkeyGestureState != .idle else { return }
        specialHotkeyGestureState = .idle
        publishSpecialGestureAction(.cancelled)
    }

    private func publishSpecialGestureAction(_ action: SpecialHotkeyGestureAction) {
        guard action != .none, let callback = onSpecialGestureAction else { return }
        Task { @MainActor in callback(action) }
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
