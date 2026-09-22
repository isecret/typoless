import XCTest
@testable import Typoless

final class HotkeyManagerRegistrationTests: XCTestCase {
    func testReplaceRestoresPreviousHotkeyWhenInstallFails() {
        let manager = HotkeyManager()
        let original = HotkeyCombo.special(
            modifiers: [HotkeyModifierSpec(key: .option, side: .left)]
        )
        let incoming = HotkeyCombo.special(
            modifiers: [HotkeyModifierSpec(key: .command, side: .right)]
        )

        manager.testInstallHandler = { combo in
            combo == incoming ? .failure("无法注册该快捷键，可能已被系统占用。") : .success
        }

        XCTAssertEqual(manager.register(hotkey: original), .success)
        XCTAssertEqual(manager.registeredHotkey, original)

        let result = manager.replace(with: incoming)
        XCTAssertEqual(result, .failure("无法注册该快捷键，可能已被系统占用。"))
        XCTAssertEqual(manager.registeredHotkey, original)
    }

    func testReplacePersistsNewHotkeyWhenInstallSucceeds() {
        let manager = HotkeyManager()
        let original = HotkeyCombo.default
        let incoming = HotkeyCombo.special(
            modifiers: [HotkeyModifierSpec(key: .function)]
        )
        manager.testInstallHandler = { _ in .success }

        XCTAssertEqual(manager.register(hotkey: original), .success)
        XCTAssertEqual(manager.replace(with: incoming), .success)
        XCTAssertEqual(manager.registeredHotkey, incoming)
    }
}
