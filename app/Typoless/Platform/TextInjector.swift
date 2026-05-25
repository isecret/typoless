import ApplicationServices
import AppKit
import Carbon
import CoreGraphics
import Foundation

/// 文本注入器：默认通过剪贴板粘贴注入，失败时回退到 AX 写入
struct TextInjector: Sendable {
    private static let focusRetryIntervals: [TimeInterval] = [0.01, 0.02, 0.04]
    private static let pasteboardPropagationDelay: TimeInterval = 0.03
    private static let fastPasteboardRestoreDelay: TimeInterval = 0.15
    private static let slowPasteboardRestoreDelay: TimeInterval = 0.8
    private static let frontmostRetryIntervals: [TimeInterval] = [0.01, 0.02, 0.04]
    private static let slowPasteboardBundleIDs = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "abnerworks.Typora"
    ]

    struct InjectionResult: Sendable {
        let path: InjectionPath
        let breakdown: InjectionBreakdown
    }

    enum InjectionPath: String, Sendable {
        case paste
        case axFallback
    }

    struct InjectionBreakdown: Sendable {
        var activateTargetMs: Int = 0
        var focusBeforeMs: Int = 0
        var pasteboardWriteMs: Int = 0
        var pasteboardPropagationMs: Int = 0
        var postPasteShortcutMs: Int = 0
        var pasteVerificationMs: Int = 0
        var axFallbackMs: Int = 0
        var pasteboardRestoreMs: Int = 0
        var totalMs: Int = 0
    }

    // MARK: - Public API

    /// 将文本注入到当前焦点应用的输入区域
    func inject(
        text: String,
        targetPID: pid_t?,
        targetBundleID: String?
    ) throws -> InjectionResult {
        guard AXIsProcessTrusted() else {
            throw TypolessError.accessibilityPermissionDenied
        }

        let injectionStart = Date()
        var breakdown = InjectionBreakdown()

        if let targetPID {
            let start = Date()
            _ = restoreTargetApplication(pid: targetPID)
            breakdown.activateTargetMs = millisecondsSince(start)
        }

        let focusBeforeStart = Date()
        let focusedElementBeforePaste = tryGetInjectableElement(targetPID: targetPID)
        breakdown.focusBeforeMs = millisecondsSince(focusBeforeStart)
        let snapshotBeforePaste = focusedElementBeforePaste.flatMap(snapshotValue(for:))

        do {
            let pasteResult = try pasteViaClipboard(text: text, targetBundleID: targetBundleID)
            breakdown.pasteboardWriteMs = pasteResult.pasteboardWriteMs
            breakdown.pasteboardPropagationMs = pasteResult.pasteboardPropagationMs
            breakdown.postPasteShortcutMs = pasteResult.postPasteShortcutMs
            breakdown.pasteboardRestoreMs = pasteResult.restoreDelayMs

            let verificationStart = Date()
            let requiresStrictVerification = Self.shouldUseStrictPasteVerification(
                targetBundleID: targetBundleID
            )

            let shouldFallback: Bool
            if requiresStrictVerification {
                let focusedElementAfterPaste = tryGetInjectableElement(targetPID: targetPID)
                let snapshotAfterPaste = focusedElementAfterPaste.flatMap(snapshotValue(for:))
                shouldFallback = Self.shouldFallbackToAX(
                    beforeValue: snapshotBeforePaste,
                    afterValue: snapshotAfterPaste
                )
            } else {
                shouldFallback = false
            }
            breakdown.pasteVerificationMs = millisecondsSince(verificationStart)

            if !shouldFallback {
                breakdown.totalMs = millisecondsSince(injectionStart)
                return InjectionResult(
                    path: .paste,
                    breakdown: breakdown
                )
            }
        } catch {
            // 粘贴主路径失败时，继续尝试 AX 回退
        }

        if let focusedElement = tryGetInjectableElement(targetPID: targetPID) {
            // 粘贴未生效时，使用 AXSelectedText 在光标位置插入（非破坏性）
            let fallbackStart = Date()
            if tryInsertViaAX(element: focusedElement, text: text) {
                breakdown.axFallbackMs = millisecondsSince(fallbackStart)
                breakdown.totalMs = millisecondsSince(injectionStart)
                return InjectionResult(
                    path: .axFallback,
                    breakdown: breakdown
                )
            }
        }

        throw TypolessError.textInjectionFailure(detail: "文本未能成功写入当前焦点输入区域")
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

    private func snapshotValue(for element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &valueRef
        )

        guard result == .success else { return nil }

        return valueRef as? String
    }

    static func shouldFallbackToAX(
        beforeValue: String?,
        afterValue: String?
    ) -> Bool {
        guard let beforeValue, let afterValue else { return false }
        return beforeValue == afterValue
    }

    // MARK: - Pasteboard Primary

    private func pasteViaClipboard(text: String, targetBundleID: String?) throws -> PasteOperationResult {
        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboard(pasteboard)

        let writeStart = Date()
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            restorePasteboard(snapshot, pasteboard: pasteboard)
            throw TypolessError.textInjectionFailure(detail: "无法写入系统剪贴板")
        }
        let pasteboardWriteMs = millisecondsSince(writeStart)

        let restoreDelay = shouldUseSlowPasteboardRestore(for: targetBundleID)
            ? Self.slowPasteboardRestoreDelay
            : Self.fastPasteboardRestoreDelay

        schedulePasteboardRestore(
            snapshot,
            after: restoreDelay
        )

        let propagationStart = Date()
        RunLoop.current.run(until: Date().addingTimeInterval(Self.pasteboardPropagationDelay))
        let pasteboardPropagationMs = millisecondsSince(propagationStart)

        let shortcutStart = Date()
        try postPasteShortcut()
        let postPasteShortcutMs = millisecondsSince(shortcutStart)

        return PasteOperationResult(
            pasteboardWriteMs: pasteboardWriteMs,
            pasteboardPropagationMs: pasteboardPropagationMs,
            postPasteShortcutMs: postPasteShortcutMs,
            restoreDelayMs: Int(restoreDelay * 1000)
        )
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

    private func schedulePasteboardRestore(
        _ snapshot: [[NSPasteboard.PasteboardType: Data]],
        after delay: TimeInterval
    ) {
        let restoreSnapshot = snapshot
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.restorePasteboard(restoreSnapshot, pasteboard: NSPasteboard.general)
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

    private static func shouldUseStrictPasteVerification(targetBundleID: String?) -> Bool {
        guard let targetBundleID else { return false }
        return slowPasteboardBundleIDs.contains(targetBundleID)
    }

    private static func resolvePasteShortcut() -> (keyCode: CGKeyCode, flags: CGEventFlags) {
        let pasteShortcut = currentPasteShortcut()
        let modifiers = pasteShortcut.modifiers.intersection(.deviceIndependentFlagsMask)
        let keyEquivalent = normalizedKeyEquivalent(from: pasteShortcut.keyEquivalent) ?? "v"
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

    private static func currentPasteShortcut() -> (keyEquivalent: String?, modifiers: NSEvent.ModifierFlags) {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                guard let item = pasteMenuItem else {
                    return (nil, .command)
                }
                return (item.keyEquivalent, item.keyEquivalentModifierMask)
            }
        }

        return DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                guard let item = pasteMenuItem else {
                    return (nil, .command)
                }
                return (item.keyEquivalent, item.keyEquivalentModifierMask)
            }
        }
    }

    @MainActor
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

    private func millisecondsSince(_ start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }
}

extension TextInjector {
    static func debugShouldUseStrictPasteVerification(targetBundleID: String?) -> Bool {
        shouldUseStrictPasteVerification(targetBundleID: targetBundleID)
    }

    static func debugPasteboardRestoreDelay(targetBundleID: String?) -> Int {
        Int(
            (slowPasteboardBundleIDs.contains(targetBundleID ?? "")
             ? slowPasteboardRestoreDelay
             : fastPasteboardRestoreDelay) * 1000
        )
    }
}

private struct PasteOperationResult: Sendable {
    let pasteboardWriteMs: Int
    let pasteboardPropagationMs: Int
    let postPasteShortcutMs: Int
    let restoreDelayMs: Int
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
