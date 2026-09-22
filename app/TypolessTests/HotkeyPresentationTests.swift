import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Typoless

final class HotkeyPresentationTests: XCTestCase {
    func testOptionSpaceUsesSeparateTokensWithoutPlus() {
        let combo = HotkeyCombo.standard(
            keyCode: UInt16(kVK_Space),
            modifiers: NSEvent.ModifierFlags.option.rawValue,
            keyLabel: "Space"
        )
        let presentation = HotkeyPresentation(combo: combo)

        XCTAssertEqual(presentation.visualTokens.map(\.visualLabel), ["⌥", "Space"])
        XCTAssertFalse(presentation.compactDescription.contains("+"))
        XCTAssertEqual(presentation.accessibilityDescription, "Option 加 空格")
    }

    func testLeftControlLeftOptionShowsLocalizedSides() {
        let combo = HotkeyCombo.special(
            modifiers: [
                HotkeyModifierSpec(key: .control, side: .left),
                HotkeyModifierSpec(key: .option, side: .left),
            ]
        )
        let presentation = HotkeyPresentation(combo: combo)

        XCTAssertEqual(presentation.visualTokens.map(\.visualLabel), ["左 ⌃", "左 ⌥"])
        XCTAssertEqual(presentation.accessibilityDescription, "左侧 Control 加 左侧 Option")
        XCTAssertFalse(presentation.visualTokens.contains(where: { $0.visualLabel.contains("L ") }))
    }

    func testLeftControlRightOptionAndLetterLKeepLetterDistinctFromSide() {
        let combo = HotkeyCombo.standard(
            keyCode: UInt16(kVK_ANSI_L),
            modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue,
            keyLabel: "L",
            physicalModifiers: [
                HotkeyModifierSpec(key: .control, side: .left),
                HotkeyModifierSpec(key: .option, side: .right),
            ]
        )
        let presentation = HotkeyPresentation(combo: combo)

        XCTAssertEqual(presentation.visualTokens.map(\.visualLabel), ["左 ⌃", "右 ⌥", "L"])
        XCTAssertEqual(presentation.accessibilityDescription, "左侧 Control 加 右侧 Option 加 字母 L")
    }

    func testEitherSideOmitsLeftRightPrefix() {
        let combo = HotkeyCombo.special(
            modifiers: [
                HotkeyModifierSpec(key: .command, side: .either),
            ]
        )
        let presentation = HotkeyPresentation(combo: combo)

        XCTAssertEqual(presentation.visualTokens.map(\.visualLabel), ["⌘"])
        XCTAssertEqual(presentation.accessibilityDescription, "Command")
    }

    func testFnTokenAndCommandFnOrder() {
        let fnOnly = HotkeyPresentation(
            combo: HotkeyCombo.special(modifiers: [HotkeyModifierSpec(key: .function)])
        )
        XCTAssertEqual(fnOnly.visualTokens.map(\.visualLabel), ["Fn / 🌐"])
        XCTAssertEqual(fnOnly.accessibilityDescription, "Fn 或地球键")

        let commandFn = HotkeyPresentation(
            combo: HotkeyCombo.special(
                modifiers: [
                    HotkeyModifierSpec(key: .function),
                    HotkeyModifierSpec(key: .command, side: .left),
                ]
            )
        )
        XCTAssertEqual(commandFn.visualTokens.map(\.visualLabel), ["左 ⌘", "Fn / 🌐"])
    }

    func testLegacyDisplayStringConfigDoesNotDriveTokens() throws {
        let json = """
        {
          "displayString": "L ⇧ + L ⌃ + Z",
          "keyCode": 6,
          "modifiers": \(NSEvent.ModifierFlags([.control, .shift]).rawValue)
        }
        """
        let combo = try JSONDecoder().decode(HotkeyCombo.self, from: Data(json.utf8))
        let presentation = HotkeyPresentation(combo: combo)

        XCTAssertEqual(presentation.visualTokens.map(\.visualLabel), ["⌃", "⇧", "Z"])
        XCTAssertFalse(presentation.visualTokens.contains(where: { $0.visualLabel.contains("L") && $0.visualLabel != "Z" }))
    }

    func testKnownSystemShortcutWarning() {
        let spotlight = HotkeyCombo.standard(
            keyCode: UInt16(kVK_Space),
            modifiers: NSEvent.ModifierFlags.command.rawValue,
            keyLabel: "Space"
        )
        XCTAssertEqual(HotkeySystemConflict.warning(for: spotlight), "此组合常用于 Spotlight。")

        let optionSpace = HotkeyCombo.default
        XCTAssertNil(HotkeySystemConflict.warning(for: optionSpace))
    }
}
