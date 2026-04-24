import ApplicationServices
import CoreGraphics
import Foundation

/// 文本注入器：优先通过 AX 写入焦点元素，失败时回退到键盘事件输入
struct TextInjector: Sendable {

    // MARK: - Public API

    /// 将文本注入到当前焦点应用的输入区域
    func inject(text: String) throws {
        guard AXIsProcessTrusted() else {
            throw TypolessError.accessibilityPermissionDenied
        }

        let focusedElement = try getFocusedElement()

        // 优先使用 AXSelectedText 在光标位置插入（非破坏性）
        if tryInsertViaAX(element: focusedElement, text: text) {
            return
        }

        // 回退到键盘事件输入
        try typeViaKeyboard(text: text)
    }

    // MARK: - AX Element Discovery

    private func getFocusedElement() throws -> AXUIElement {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedAppRef: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedAppRef
        )
        guard appResult == .success else {
            throw TypolessError.textInjectionFailure(detail: "未找到焦点应用")
        }

        var focusedElementRef: CFTypeRef?
        let elemResult = AXUIElementCopyAttributeValue(
            focusedAppRef as! AXUIElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        guard elemResult == .success else {
            throw TypolessError.textInjectionFailure(detail: "未找到焦点元素")
        }

        return focusedElementRef as! AXUIElement
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

    /// 通过 CGEvent Unicode 键盘事件逐块输入文本
    private func typeViaKeyboard(text: String) throws {
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
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
