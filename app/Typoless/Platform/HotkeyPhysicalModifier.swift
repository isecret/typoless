import AppKit
import Carbon.HIToolbox
import Foundation

enum HotkeyPhysicalModifier: UInt16, CaseIterable, Hashable, Sendable {
    case leftCommand = 55
    case rightCommand = 54
    case leftOption = 58
    case rightOption = 61
    case leftControl = 59
    case rightControl = 62
    case leftShift = 56
    case rightShift = 60

    static let modifierKeyCodes: Set<UInt16> = Set(Self.allCases.map(\.rawValue))

    var spec: HotkeyModifierSpec {
        switch self {
        case .leftCommand:
            HotkeyModifierSpec(key: .command, side: .left)
        case .rightCommand:
            HotkeyModifierSpec(key: .command, side: .right)
        case .leftOption:
            HotkeyModifierSpec(key: .option, side: .left)
        case .rightOption:
            HotkeyModifierSpec(key: .option, side: .right)
        case .leftControl:
            HotkeyModifierSpec(key: .control, side: .left)
        case .rightControl:
            HotkeyModifierSpec(key: .control, side: .right)
        case .leftShift:
            HotkeyModifierSpec(key: .shift, side: .left)
        case .rightShift:
            HotkeyModifierSpec(key: .shift, side: .right)
        }
    }

    var genericFlags: NSEvent.ModifierFlags {
        spec.key.genericFlags
    }

    private var deviceMask: UInt {
        switch self {
        case .leftControl:
            0x00000001
        case .leftShift:
            0x00000002
        case .rightShift:
            0x00000004
        case .leftCommand:
            0x00000008
        case .rightCommand:
            0x00000010
        case .leftOption:
            0x00000020
        case .rightOption:
            0x00000040
        case .rightControl:
            0x00002000
        }
    }

    static func pressedSet(from flags: NSEvent.ModifierFlags) -> Set<HotkeyPhysicalModifier> {
        let rawValue = flags.rawValue
        return Set(
            allCases.filter { modifier in
                rawValue & modifier.deviceMask != 0
            }
        )
    }
}

extension Set where Element == HotkeyPhysicalModifier {
    var genericFlags: NSEvent.ModifierFlags {
        reduce(into: NSEvent.ModifierFlags()) { partialResult, modifier in
            partialResult.formUnion(modifier.genericFlags)
        }
    }
}

extension HotkeyCombo {
    private var normalizedRecordedModifiers: [HotkeyModifierSpec] {
        specialModifiers.sorted { lhs, rhs in
            if lhs.key.sortPriority != rhs.key.sortPriority {
                return lhs.key.sortPriority < rhs.key.sortPriority
            }
            return lhs.side.rawValue < rhs.side.rawValue
        }
    }

    var hasPhysicalStandardModifiers: Bool {
        kind == .standard && !specialModifiers.isEmpty
    }

    func matchesSpecialPressedModifiers(_ pressed: Set<HotkeyPhysicalModifier>) -> Bool {
        guard kind == .special else { return false }
        return matchesRecordedModifiers(pressed)
    }

    func matchesStandardPressedModifiers(
        keyCode: UInt16,
        pressed: Set<HotkeyPhysicalModifier>
    ) -> Bool {
        guard kind == .standard, self.keyCode == keyCode else { return false }
        guard hasPhysicalStandardModifiers else { return false }
        return matchesRecordedModifiers(pressed)
    }

    private func matchesRecordedModifiers(_ pressed: Set<HotkeyPhysicalModifier>) -> Bool {
        let expected = normalizedRecordedModifiers
        guard pressed.count == expected.count else { return false }

        var unmatched = Array(pressed)
        for spec in expected {
            guard let index = unmatched.firstIndex(where: { physical in
                physical.spec.key == spec.key
                    && (spec.side == .either || physical.spec.side == spec.side)
            }) else {
                return false
            }
            unmatched.remove(at: index)
        }

        return unmatched.isEmpty
    }
}
