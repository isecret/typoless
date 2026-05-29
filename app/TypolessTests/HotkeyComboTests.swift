import AppKit
import XCTest
@testable import Typoless

final class HotkeyComboTests: XCTestCase {

    func testLegacyStandardHotkeyDecodes() throws {
        let json = """
        {
          "displayString": "⌥ Space",
          "keyCode": 49,
          "modifiers": 524576
        }
        """

        let combo = try JSONDecoder().decode(HotkeyCombo.self, from: Data(json.utf8))

        XCTAssertEqual(combo.kind, .standard)
        XCTAssertEqual(combo.keyCode, 49)
        XCTAssertEqual(combo.modifiers, 524576)
        XCTAssertEqual(combo.displayString, "⌥ + Space")
        XCTAssertTrue(combo.specialModifiers.isEmpty)
    }

    func testSpecialHotkeyRoundTripsThroughCodable() throws {
        let original = HotkeyCombo.special(
            modifiers: [
                HotkeyModifierSpec(key: .command, side: .left),
                HotkeyModifierSpec(key: .option, side: .right),
            ]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyCombo.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.keyCode, nil)
    }

    func testSpecialHotkeyUsesAbbreviatedDisplayString() {
        let combo = HotkeyCombo.special(
            modifiers: [
                HotkeyModifierSpec(key: .command, side: .left),
                HotkeyModifierSpec(key: .option, side: .right),
                HotkeyModifierSpec(key: .control),
            ]
        )

        XCTAssertEqual(combo.displayString, "⌃ + R ⌥ + L ⌘")
    }

    func testStandardHotkeyUsesAbbreviatedDisplayString() {
        let combo = HotkeyCombo.standard(
            keyCode: 0,
            modifiers: NSEvent.ModifierFlags([.control, .option, .command]).rawValue,
            keyLabel: "A"
        )

        XCTAssertEqual(combo.displayString, "⌃ + ⌥ + ⌘ + A")
    }

    func testStandardHotkeyUsesPhysicalModifierDisplayStringWhenAvailable() {
        let combo = HotkeyCombo.standard(
            keyCode: 6,
            modifiers: NSEvent.ModifierFlags([.control, .shift]).rawValue,
            keyLabel: "Z",
            physicalModifiers: [
                HotkeyModifierSpec(key: .shift, side: .left),
                HotkeyModifierSpec(key: .control, side: .left),
            ]
        )

        XCTAssertEqual(combo.displayString, "L ⌃ + L ⇧ + Z")
    }

    func testStandardHotkeyRoundTripsPhysicalModifiersThroughCodable() throws {
        let original = HotkeyCombo.standard(
            keyCode: 6,
            modifiers: NSEvent.ModifierFlags([.control, .shift]).rawValue,
            keyLabel: "Z",
            physicalModifiers: [
                HotkeyModifierSpec(key: .shift, side: .left),
                HotkeyModifierSpec(key: .control, side: .left),
            ]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyCombo.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.displayString, "L ⌃ + L ⇧ + Z")
    }

    func testSideQualifiedStandardHotkeyDecodesKeyLabelFromDisplayString() throws {
        let json = """
        {
          "kind": "standard",
          "displayString": "L ⇧ + L ⌃ + Z",
          "keyCode": 6,
          "modifiers": \(NSEvent.ModifierFlags([.control, .shift]).rawValue)
        }
        """

        let combo = try JSONDecoder().decode(HotkeyCombo.self, from: Data(json.utf8))

        XCTAssertEqual(combo.displayString, "⌃ + ⇧ + Z")
        XCTAssertTrue(combo.specialModifiers.isEmpty)
    }

    func testSpecialHotkeyMatchesSpecificPressedModifiers() {
        let combo = HotkeyCombo.special(
            modifiers: [
                HotkeyModifierSpec(key: .command, side: .left),
                HotkeyModifierSpec(key: .option, side: .right),
            ]
        )

        XCTAssertTrue(combo.matchesSpecialPressedModifiers([.leftCommand, .rightOption]))
        XCTAssertFalse(combo.matchesSpecialPressedModifiers([.leftCommand, .leftOption]))
        XCTAssertFalse(combo.matchesSpecialPressedModifiers([.leftCommand, .rightOption, .leftShift]))
    }

    func testStandardHotkeyMatchesSpecificPressedModifiers() {
        let combo = HotkeyCombo.standard(
            keyCode: 6,
            modifiers: NSEvent.ModifierFlags([.control, .shift]).rawValue,
            keyLabel: "Z",
            physicalModifiers: [
                HotkeyModifierSpec(key: .shift, side: .left),
                HotkeyModifierSpec(key: .control, side: .left),
            ]
        )

        XCTAssertTrue(combo.matchesStandardPressedModifiers(keyCode: 6, pressed: [.leftControl, .leftShift]))
        XCTAssertFalse(combo.matchesStandardPressedModifiers(keyCode: 6, pressed: [.rightControl, .leftShift]))
        XCTAssertFalse(combo.matchesStandardPressedModifiers(keyCode: 7, pressed: [.leftControl, .leftShift]))
    }

    func testPhysicalModifierSetBuildsGenericFlags() {
        let flags = Set<HotkeyPhysicalModifier>([.leftControl, .rightOption]).genericFlags

        XCTAssertTrue(flags.contains(.control))
        XCTAssertTrue(flags.contains(.option))
        XCTAssertFalse(flags.contains(.command))
    }
}
