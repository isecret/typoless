import XCTest
@testable import Typoless

final class HotkeyManagerSpecialEventTests: XCTestCase {

    private func fnHotkey() -> HotkeyCombo {
        HotkeyCombo.special(modifiers: [HotkeyModifierSpec(key: .function)])
    }

    private func sideQualifiedHotkey() -> HotkeyCombo {
        HotkeyCombo.special(
            modifiers: [
                HotkeyModifierSpec(key: .command, side: .left),
                HotkeyModifierSpec(key: .option, side: .right),
            ]
        )
    }

    private func resolve(
        pressed: Set<HotkeyPhysicalModifier>,
        hotkey: HotkeyCombo,
        isKeyDown: Bool,
        isSuspended: Bool
    ) -> SpecialHotkeyAction {
        HotkeyManager.resolveSpecialEventAction(
            pressed: pressed,
            hotkey: hotkey,
            isKeyDown: isKeyDown,
            isSuspended: isSuspended
        )
    }

    func testFnPressTriggersWhenIdle() {
        XCTAssertEqual(
            resolve(pressed: [.function], hotkey: fnHotkey(), isKeyDown: false, isSuspended: false),
            .press
        )
    }

    func testHeldFnDoesNotRetrigger() {
        // 按住期间重复的 flagsChanged（其他修饰键状态变化）不重复触发
        XCTAssertEqual(
            resolve(pressed: [.function], hotkey: fnHotkey(), isKeyDown: true, isSuspended: false),
            .none
        )
    }

    func testFnReleaseWhileDownEndsPress() {
        XCTAssertEqual(
            resolve(pressed: [], hotkey: fnHotkey(), isKeyDown: true, isSuspended: false),
            .release
        )
    }

    func testFnReleaseWhileIdleIsIgnored() {
        XCTAssertEqual(
            resolve(pressed: [], hotkey: fnHotkey(), isKeyDown: false, isSuspended: false),
            .none
        )
    }

    func testSuspendedSuppressesPressAndRelease() {
        XCTAssertEqual(
            resolve(pressed: [.function], hotkey: fnHotkey(), isKeyDown: false, isSuspended: true),
            .none
        )
        XCTAssertEqual(
            resolve(pressed: [], hotkey: fnHotkey(), isKeyDown: true, isSuspended: true),
            .none
        )
    }

    func testExtraModifierHeldWithFnDoesNotTrigger() {
        // 按住 Fn 再按其他修饰键（或 F1–F12 等带 .function 标志的键）不触发纯 Fn 快捷键
        XCTAssertEqual(
            resolve(
                pressed: [.function, .leftCommand],
                hotkey: fnHotkey(),
                isKeyDown: false,
                isSuspended: false
            ),
            .none
        )
    }

    func testFnComboHotkeyMatchesExactPressedSet() {
        let combo = HotkeyCombo.special(
            modifiers: [
                HotkeyModifierSpec(key: .function),
                HotkeyModifierSpec(key: .command, side: .left),
            ]
        )

        XCTAssertEqual(
            resolve(pressed: [.function, .leftCommand], hotkey: combo, isKeyDown: false, isSuspended: false),
            .press
        )
        XCTAssertEqual(
            resolve(pressed: [.function], hotkey: combo, isKeyDown: false, isSuspended: false),
            .none
        )
    }

    func testSideQualifiedHotkeyStillMatchesAndRejectsFunctionInPressedSet() {
        let hotkey = sideQualifiedHotkey()

        XCTAssertEqual(
            resolve(pressed: [.leftCommand, .rightOption], hotkey: hotkey, isKeyDown: false, isSuspended: false),
            .press
        )
        // 旧快捷键的精确匹配语义：pressed 多出 Fn 时不触发
        XCTAssertEqual(
            resolve(
                pressed: [.leftCommand, .rightOption, .function],
                hotkey: hotkey,
                isKeyDown: false,
                isSuspended: false
            ),
            .none
        )
    }
}
