import AppKit
import Carbon.HIToolbox
import Foundation

struct HotkeyToken: Equatable, Identifiable, Hashable, Sendable {
    let id: String
    let visualLabel: String
    let accessibilityLabel: String
}

struct HotkeyPresentation: Equatable, Sendable {
    let visualTokens: [HotkeyToken]
    let compactDescription: String
    let accessibilityDescription: String

    init(combo: HotkeyCombo) {
        self.init(
            modifiers: combo.kind == .special || combo.hasPhysicalStandardModifiers
                ? combo.specialModifiers
                : Self.genericModifierSpecs(from: combo.modifiers),
            keyCode: combo.kind == .standard ? combo.keyCode : nil
        )
    }

    init(modifiers: [HotkeyModifierSpec], keyCode: UInt16? = nil) {
        var tokens: [HotkeyToken] = modifiers
            .sorted(by: HotkeyPresentation.compareModifierSpecs)
            .map(Self.token(for:))

        if let keyCode {
            tokens.append(Self.keyToken(for: keyCode))
        }

        visualTokens = tokens
        compactDescription = tokens.map(\.visualLabel).joined(separator: " ")
        accessibilityDescription = Self.joinAccessibility(tokens.map(\.accessibilityLabel))
    }

    static func compareModifierSpecs(_ lhs: HotkeyModifierSpec, _ rhs: HotkeyModifierSpec) -> Bool {
        if lhs.key.sortPriority != rhs.key.sortPriority {
            return lhs.key.sortPriority < rhs.key.sortPriority
        }
        return sidePriority(lhs.side) < sidePriority(rhs.side)
    }

    private static func sidePriority(_ side: HotkeyModifierSide) -> Int {
        switch side {
        case .either:
            0
        case .left:
            1
        case .right:
            2
        }
    }

    private static func genericModifierSpecs(from modifiers: UInt) -> [HotkeyModifierSpec] {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var specs: [HotkeyModifierSpec] = []
        if flags.contains(.control) { specs.append(HotkeyModifierSpec(key: .control)) }
        if flags.contains(.option) { specs.append(HotkeyModifierSpec(key: .option)) }
        if flags.contains(.shift) { specs.append(HotkeyModifierSpec(key: .shift)) }
        if flags.contains(.command) { specs.append(HotkeyModifierSpec(key: .command)) }
        if flags.contains(HotkeyModifierKey.functionFlag) {
            specs.append(HotkeyModifierSpec(key: .function))
        }
        return specs
    }

    private static func token(for spec: HotkeyModifierSpec) -> HotkeyToken {
        let visualSide: String
        let spokenSide: String
        switch spec.side {
        case .left:
            visualSide = "左 "
            spokenSide = "左侧 "
        case .right:
            visualSide = "右 "
            spokenSide = "右侧 "
        case .either:
            visualSide = ""
            spokenSide = ""
        }

        if spec.key == .function {
            return HotkeyToken(
                id: "function",
                visualLabel: "Fn / 🌐",
                accessibilityLabel: "Fn 或地球键"
            )
        }

        return HotkeyToken(
            id: "\(spec.side.rawValue)-\(spec.key.rawValue)",
            visualLabel: "\(visualSide)\(spec.key.symbol)",
            accessibilityLabel: "\(spokenSide)\(spec.key.displayName)"
        )
    }

    static func keyToken(for keyCode: UInt16) -> HotkeyToken {
        let visual = keyVisualLabel(for: keyCode)
        return HotkeyToken(
            id: "key-\(keyCode)",
            visualLabel: visual,
            accessibilityLabel: keyAccessibilityLabel(visual: visual, keyCode: keyCode)
        )
    }

    static func keyVisualLabel(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Space:
            "Space"
        case kVK_Tab:
            "Tab"
        case kVK_Return:
            "Return"
        case kVK_Escape:
            "Esc"
        case kVK_Delete:
            "Delete"
        case kVK_ForwardDelete:
            "Forward Delete"
        case kVK_LeftArrow:
            "←"
        case kVK_RightArrow:
            "→"
        case kVK_UpArrow:
            "↑"
        case kVK_DownArrow:
            "↓"
        default:
            translatedCharacter(for: keyCode) ?? "Key \(keyCode)"
        }
    }

    static func keyLabel(from event: NSEvent) -> String {
        keyVisualLabel(for: UInt16(event.keyCode))
    }

    private static func keyAccessibilityLabel(visual: String, keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Space:
            "空格"
        case kVK_LeftArrow:
            "左方向键"
        case kVK_RightArrow:
            "右方向键"
        case kVK_UpArrow:
            "上方向键"
        case kVK_DownArrow:
            "下方向键"
        case kVK_ForwardDelete:
            "向前删除"
        default:
            if visual.count == 1, visual.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) {
                "字母 \(visual)"
            } else {
                visual
            }
        }
    }

    private static func joinAccessibility(_ parts: [String]) -> String {
        switch parts.count {
        case 0:
            "未设置"
        case 1:
            parts[0]
        default:
            parts.joined(separator: " 加 ")
        }
    }

    private static func translatedCharacter(for keyCode: UInt16) -> String? {
        var deadKeyState: UInt32 = 0
        let maxLength = 4
        var chars = [UniChar](repeating: 0, count: maxLength)
        var actualLength = 0

        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawLayout = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }

        let layoutData = Unmanaged<CFData>.fromOpaque(rawLayout).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return nil
            }

            let status = UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                maxLength,
                &actualLength,
                &chars
            )
            guard status == noErr, actualLength > 0 else { return nil }
            let value = String(utf16CodeUnits: chars, count: actualLength)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            return value.uppercased()
        }
    }
}

enum HotkeySystemConflict {
    static func warning(for combo: HotkeyCombo) -> String? {
        guard combo.kind == .standard, let keyCode = combo.keyCode else { return nil }
        let flags = NSEvent.ModifierFlags(rawValue: combo.modifiers)
            .intersection([.command, .option, .control, .shift])

        if keyCode == UInt16(kVK_Space), flags == .command {
            return "此组合常用于 Spotlight。"
        }
        if keyCode == UInt16(kVK_Space), flags == .control {
            return "此组合常用于切换输入法。"
        }
        if keyCode == UInt16(kVK_Tab), flags == .command {
            return "此组合常用于切换应用。"
        }
        return nil
    }
}

enum HotkeyRecordingPhase: Equatable {
    case idle
    case waiting
    case previewingModifiers
}
