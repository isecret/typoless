import ApplicationServices
import AppKit
import Carbon
import CoreGraphics
import Foundation

/// 文本注入器：优先通过 AX 写入焦点元素，失败时回退到键盘事件输入
struct TextInjector: Sendable {
    private static let focusRetryIntervals: [TimeInterval] = [0.03, 0.05, 0.08, 0.12, 0.18]
    private static let pasteboardPropagationDelay: TimeInterval = 0.12
    private static let pasteCommandSettleDelay: TimeInterval = 0.35
    private static let slowPasteboardRestoreDelay: TimeInterval = 1.5
    private static let frontmostRetryIntervals: [TimeInterval] = [0.03, 0.05, 0.08, 0.12]
    private static let slowPasteboardBundleIDs = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "abnerworks.Typora"
    ]

    // MARK: - Public API

    /// 将文本注入到当前焦点应用的输入区域
    func inject(
        text: String,
        targetPID: pid_t?,
        targetBundleID: String?,
        pasteboardPreferredBundleIDs: [String]
    ) throws {
        guard AXIsProcessTrusted() else {
            throw TypolessError.accessibilityPermissionDenied
        }

        if shouldUsePasteboardInjection(
            targetBundleID: targetBundleID,
            preferredBundleIDs: pasteboardPreferredBundleIDs
        ) {
            try pasteViaClipboard(text: text, targetBundleID: targetBundleID)
            return
        }

        if let focusedElement = tryGetInjectableElement(targetPID: targetPID) {
            // 优先使用 AXSelectedText 在光标位置插入（非破坏性）
            if tryInsertViaAX(element: focusedElement, text: text) {
                return
            }
        }

        // 焦点元素缺失或 AX 写入失败时，回退到键盘事件输入
        try typeViaKeyboard(text: text, targetPID: targetPID)
    }

    // MARK: - AX Element Discovery

    private func tryGetInjectableElement(targetPID: pid_t?) -> AXUIElement? {
        if let targetPID,
           restoreTargetApplication(pid: targetPID),
           let element = tryGetFocusedElement(for: targetPID) {
            return element
        }

        let systemWide = AXUIElementCreateSystemWide()

        var focusedAppRef: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedAppRef
        )
        guard appResult == .success else {
            return nil
        }

        var focusedElementRef: CFTypeRef?
        let elemResult = AXUIElementCopyAttributeValue(
            focusedAppRef as! AXUIElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        guard elemResult == .success else {
            return nil
        }

        return (focusedElementRef as! AXUIElement)
    }

    private func tryGetFocusedElement(for pid: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)

        for interval in Self.focusRetryIntervals {
            var focusedElementRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(
                appElement,
                kAXFocusedUIElementAttribute as CFString,
                &focusedElementRef
            )

            if result == .success, let focusedElementRef {
                return (focusedElementRef as! AXUIElement)
            }

            RunLoop.current.run(until: Date().addingTimeInterval(interval))
        }

        return nil
    }

    private func restoreTargetApplication(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            return false
        }

        if app.isHidden {
            app.unhide()
        }

        _ = app.activate(options: [.activateAllWindows])

        for interval in Self.frontmostRetryIntervals {
            if app.isActive || NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(interval))
        }

        return app.isActive || NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }

    private func shouldUsePasteboardInjection(
        targetBundleID: String?,
        preferredBundleIDs: [String]
    ) -> Bool {
        guard let targetBundleID else { return false }

        return preferredBundleIDs.contains { entry in
            let normalizedEntry = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedEntry.isEmpty else { return false }

            if normalizedEntry.hasSuffix("*") {
                let prefix = String(normalizedEntry.dropLast())
                return targetBundleID.hasPrefix(prefix)
            }

            return targetBundleID == normalizedEntry
        }
    }

    // MARK: - AX Insertion

    /// 尝试通过 AXSelectedText 在光标位置插入文本
    private func tryInsertViaAX(element: AXUIElement, text: String) -> Bool {
        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        )
        return result == .success
    }

    // MARK: - Keyboard Fallback

    private func pasteViaClipboard(text: String, targetBundleID: String?) throws {
        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboard(pasteboard)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            restorePasteboard(snapshot, pasteboard: pasteboard)
            throw TypolessError.textInjectionFailure(detail: "无法写入系统剪贴板")
        }

        let restoreDelay = shouldUseSlowPasteboardRestore(for: targetBundleID)
            ? Self.slowPasteboardRestoreDelay
            : Self.pasteCommandSettleDelay

        defer {
            RunLoop.current.run(until: Date().addingTimeInterval(restoreDelay))
            restorePasteboard(snapshot, pasteboard: pasteboard)
        }

        RunLoop.current.run(until: Date().addingTimeInterval(Self.pasteboardPropagationDelay))

        try postPasteShortcut()
    }

    private func snapshotPasteboard(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var snapshot: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    snapshot[type] = data
                }
            }
            return snapshot
        }
    }

    private func restorePasteboard(
        _ snapshot: [[NSPasteboard.PasteboardType: Data]],
        pasteboard: NSPasteboard
    ) {
        pasteboard.clearContents()

        guard !snapshot.isEmpty else { return }

        for itemSnapshot in snapshot {
            let item = NSPasteboardItem()
            for (type, data) in itemSnapshot {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
    }

    /// 通过 CGEvent Unicode 键盘事件逐块输入文本
    /// 终端类应用对 postToPid 支持不稳定，恢复目标应用焦点后统一走全局 HID 事件更可靠。
    private func typeViaKeyboard(text: String, targetPID: pid_t?) throws {
        if let targetPID {
            _ = restoreTargetApplication(pid: targetPID)
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let utf16Units = Array(text.utf16)
        let chunkSize = 20

        for offset in stride(from: 0, to: utf16Units.count, by: chunkSize) {
            let end = min(offset + chunkSize, utf16Units.count)
            var chunk = Array(utf16Units[offset..<end])

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else {
                throw TypolessError.textInjectionFailure(detail: "无法创建键盘事件")
            }

            keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            keyUp.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)

            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private func postPasteShortcut() throws {
        let shortcut = Self.resolvePasteShortcut()

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false)
        else {
            throw TypolessError.textInjectionFailure(detail: "无法创建粘贴事件")
        }

        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        keyDown.flags = shortcut.flags
        keyUp.flags = shortcut.flags
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }

    private func shouldUseSlowPasteboardRestore(for targetBundleID: String?) -> Bool {
        guard let targetBundleID else { return false }
        return Self.slowPasteboardBundleIDs.contains(targetBundleID)
    }

    private static func resolvePasteShortcut() -> (keyCode: CGKeyCode, flags: CGEventFlags) {
        let modifiers = pasteMenuItem?.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) ?? .command
        let keyEquivalent = normalizedKeyEquivalent(from: pasteMenuItem?.keyEquivalent) ?? "v"
        let keyboardLayout = KeyboardLayout.current

        let keyCode: CGKeyCode
        if keyboardLayout.commandSwitchesToQWERTY, modifiers.contains(.command) {
            keyCode = keyboardLayout.qwertyKeyCode(for: keyEquivalent) ?? CGKeyCode(kVK_ANSI_V)
        } else {
            keyCode = keyboardLayout.keyCode(for: keyEquivalent)
                ?? keyboardLayout.qwertyKeyCode(for: keyEquivalent)
                ?? CGKeyCode(kVK_ANSI_V)
        }

        let flags = CGEventFlags(rawValue: UInt64(cgEventFlags(from: modifiers).rawValue) | 0x000008)
        return (keyCode, flags)
    }

    private static var pasteMenuItem: NSMenuItem? {
        NSApp.mainMenu?.items
            .flatMap { $0.submenu?.items ?? [] }
            .first { $0.action == #selector(NSText.paste) }
    }

    private static func normalizedKeyEquivalent(from keyEquivalent: String?) -> String? {
        guard let value = keyEquivalent?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        if value.count == 1 {
            return value.lowercased()
        }

        return value
    }

    private static func cgEventFlags(from modifiers: NSEvent.ModifierFlags) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        return flags
    }
}

private struct KeyboardLayout {
    static var current: KeyboardLayout { KeyboardLayout() }

    var commandSwitchesToQWERTY: Bool {
        localizedName.hasSuffix("⌘")
    }

    private let inputSource: TISInputSource

    private var localizedName: String {
        guard let value = TISGetInputSourceProperty(inputSource, kTISPropertyLocalizedName) else {
            return ""
        }

        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    }

    init() {
        inputSource = TISCopyCurrentKeyboardLayoutInputSource().takeUnretainedValue()
    }

    func keyCode(for keyEquivalent: String) -> CGKeyCode? {
        guard let scalar = keyEquivalent.unicodeScalars.first else { return nil }

        for keyCode in 0...127 {
            guard let produced = translatedCharacters(for: CGKeyCode(keyCode)) else { continue }
            if produced.caseInsensitiveCompare(String(scalar)) == .orderedSame {
                return CGKeyCode(keyCode)
            }
        }

        return qwertyKeyCode(for: keyEquivalent)
    }

    func qwertyKeyCode(for keyEquivalent: String) -> CGKeyCode? {
        guard let scalar = keyEquivalent.lowercased().unicodeScalars.first else { return nil }
        return Self.qwertyKeyCodes[scalar]
    }

    private func translatedCharacters(for keyCode: CGKeyCode) -> String? {
        guard let rawLayoutData = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }

        let layoutData = unsafeBitCast(rawLayoutData, to: CFData.self) as Data
        return layoutData.withUnsafeBytes { rawBuffer in
            guard let keyboardLayout = rawBuffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return nil
            }

            var deadKeyState: UInt32 = 0
            var length: Int = 0
            var buffer = [UniChar](repeating: 0, count: 4)

            let result = UCKeyTranslate(
                keyboardLayout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                buffer.count,
                &length,
                &buffer
            )

            guard result == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: buffer, count: length)
        }
    }

    private static let qwertyKeyCodes: [Unicode.Scalar: CGKeyCode] = [
        "a": CGKeyCode(kVK_ANSI_A),
        "b": CGKeyCode(kVK_ANSI_B),
        "c": CGKeyCode(kVK_ANSI_C),
        "d": CGKeyCode(kVK_ANSI_D),
        "e": CGKeyCode(kVK_ANSI_E),
        "f": CGKeyCode(kVK_ANSI_F),
        "g": CGKeyCode(kVK_ANSI_G),
        "h": CGKeyCode(kVK_ANSI_H),
        "i": CGKeyCode(kVK_ANSI_I),
        "j": CGKeyCode(kVK_ANSI_J),
        "k": CGKeyCode(kVK_ANSI_K),
        "l": CGKeyCode(kVK_ANSI_L),
        "m": CGKeyCode(kVK_ANSI_M),
        "n": CGKeyCode(kVK_ANSI_N),
        "o": CGKeyCode(kVK_ANSI_O),
        "p": CGKeyCode(kVK_ANSI_P),
        "q": CGKeyCode(kVK_ANSI_Q),
        "r": CGKeyCode(kVK_ANSI_R),
        "s": CGKeyCode(kVK_ANSI_S),
        "t": CGKeyCode(kVK_ANSI_T),
        "u": CGKeyCode(kVK_ANSI_U),
        "v": CGKeyCode(kVK_ANSI_V),
        "w": CGKeyCode(kVK_ANSI_W),
        "x": CGKeyCode(kVK_ANSI_X),
        "y": CGKeyCode(kVK_ANSI_Y),
        "z": CGKeyCode(kVK_ANSI_Z),
        "0": CGKeyCode(kVK_ANSI_0),
        "1": CGKeyCode(kVK_ANSI_1),
        "2": CGKeyCode(kVK_ANSI_2),
        "3": CGKeyCode(kVK_ANSI_3),
        "4": CGKeyCode(kVK_ANSI_4),
        "5": CGKeyCode(kVK_ANSI_5),
        "6": CGKeyCode(kVK_ANSI_6),
        "7": CGKeyCode(kVK_ANSI_7),
        "8": CGKeyCode(kVK_ANSI_8),
        "9": CGKeyCode(kVK_ANSI_9)
    ]
}
