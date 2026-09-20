import XCTest
@testable import Typoless

final class HotkeyRecorderControlTests: XCTestCase {
    func testModifierPreviewDoesNotRegressWhenReleasingPartOfLargestCombination() {
        let initial = HotkeyRecorderControl.resolveModifierPreviewState(
            pressed: [.leftControl, .leftShift],
            previousLargest: []
        )
        XCTAssertEqual(initial.preview, [.leftControl, .leftShift])
        XCTAssertEqual(initial.largest, [.leftControl, .leftShift])

        let expanded = HotkeyRecorderControl.resolveModifierPreviewState(
            pressed: [.leftControl, .leftShift, .rightCommand],
            previousLargest: initial.largest
        )
        XCTAssertEqual(expanded.preview, [.leftControl, .leftShift, .rightCommand])
        XCTAssertEqual(expanded.largest, [.leftControl, .leftShift, .rightCommand])

        let partialRelease = HotkeyRecorderControl.resolveModifierPreviewState(
            pressed: [.leftControl, .leftShift],
            previousLargest: expanded.largest
        )
        XCTAssertEqual(partialRelease.preview, [.leftControl, .leftShift, .rightCommand])
        XCTAssertEqual(partialRelease.largest, [.leftControl, .leftShift, .rightCommand])
    }

    func testFunctionKeyCodeIsTreatedAsModifier() {
        // Fn 的 keyDown 必须被吞掉，避免把 kVK_Function 当普通键提交
        XCTAssertTrue(HotkeyPhysicalModifier.modifierKeyCodes.contains(63))
        XCTAssertEqual(
            HotkeyPhysicalModifier(rawValue: 63)?.spec,
            HotkeyModifierSpec(key: .function, side: .either)
        )
    }

    func testFnPreviewShowsAndCommitsOnRelease() {
        let pressed = HotkeyRecorderControl.resolveModifierPreviewState(
            pressed: [.function],
            previousLargest: []
        )
        XCTAssertEqual(pressed.preview, [.function])
        XCTAssertEqual(pressed.largest, [.function])

        // 松开后 pressed 为空，录制控件按 largest 提交 Fn 特殊快捷键
        let released = HotkeyRecorderControl.resolveModifierPreviewState(
            pressed: [],
            previousLargest: pressed.largest
        )
        XCTAssertEqual(released.preview, [.function])

        let combo = HotkeyCombo.special(
            modifiers: released.largest.map(\.spec)
        )
        XCTAssertEqual(combo.displayString, "Fn")
    }

    func testFnPreviewCombinedWithOtherModifier() {
        let state = HotkeyRecorderControl.resolveModifierPreviewState(
            pressed: [.function, .leftCommand],
            previousLargest: []
        )
        XCTAssertEqual(state.preview, [.function, .leftCommand])
        XCTAssertEqual(state.largest, [.function, .leftCommand])
    }
}
