import XCTest
@testable import Typoless

final class HotkeyManagerSpecialEventTests: XCTestCase {

    func testRightCommandCleanTapTriggersOnlyAfterRelease() {
        let hotkey = HotkeyCombo.special(
            modifiers: [HotkeyModifierSpec(key: .command, side: .right)]
        )

        let pressed = HotkeyManager.resolveSpecialGestureEvent(
            .modifierFlagsChanged([.rightCommand]),
            hotkey: hotkey,
            state: .idle,
            isSuspended: false
        )
        XCTAssertEqual(pressed, SpecialHotkeyTransition(state: .armed, action: .began))
        XCTAssertEqual(pressed.action, .began)

        let released = HotkeyManager.resolveSpecialGestureEvent(
            .modifierFlagsChanged([]),
            hotkey: hotkey,
            state: pressed.state,
            isSuspended: false
        )
        XCTAssertEqual(released, SpecialHotkeyTransition(state: .idle, shouldTrigger: true))
        XCTAssertEqual(released.action, .confirmed)
    }

    func testRightCommandFollowedByRegularKeyCancelsGesture() {
        let hotkey = HotkeyCombo.special(
            modifiers: [HotkeyModifierSpec(key: .command, side: .right)]
        )
        let armed = HotkeyManager.resolveSpecialGestureEvent(
            .modifierFlagsChanged([.rightCommand]),
            hotkey: hotkey,
            state: .idle,
            isSuspended: false
        )

        let keyDown = HotkeyManager.resolveSpecialGestureEvent(
            .keyDown(46), // M
            hotkey: hotkey,
            state: armed.state,
            isSuspended: false
        )
        XCTAssertEqual(keyDown, SpecialHotkeyTransition(state: .cancelled, shouldTrigger: false))
        XCTAssertEqual(keyDown.action, .none)

        let released = HotkeyManager.resolveSpecialGestureEvent(
            .modifierFlagsChanged([]),
            hotkey: hotkey,
            state: keyDown.state,
            isSuspended: false
        )
        XCTAssertEqual(released, SpecialHotkeyTransition(state: .idle, action: .cancelled))
        XCTAssertEqual(released.action, .cancelled)
    }

    func testExtraModifierCancelsArmedGestureUntilAllModifiersAreReleased() {
        let hotkey = HotkeyCombo.special(
            modifiers: [HotkeyModifierSpec(key: .command, side: .right)]
        )
        let armed = HotkeyManager.resolveSpecialGestureEvent(
            .modifierFlagsChanged([.rightCommand]),
            hotkey: hotkey,
            state: .idle,
            isSuspended: false
        )

        let extraModifier = HotkeyManager.resolveSpecialGestureEvent(
            .modifierFlagsChanged([.rightCommand, .leftShift]),
            hotkey: hotkey,
            state: armed.state,
            isSuspended: false
        )
        XCTAssertEqual(extraModifier, SpecialHotkeyTransition(state: .cancelled, shouldTrigger: false))

        let targetStillHeld = HotkeyManager.resolveSpecialGestureEvent(
            .modifierFlagsChanged([.rightCommand]),
            hotkey: hotkey,
            state: extraModifier.state,
            isSuspended: false
        )
        XCTAssertEqual(targetStillHeld, SpecialHotkeyTransition(state: .cancelled, shouldTrigger: false))
    }

    func testExtraModifierPressedFirstPreventsArmingUntilCompleteRelease() {
        let hotkey = HotkeyCombo.special(
            modifiers: [HotkeyModifierSpec(key: .command, side: .right)]
        )
        let extraFirst = HotkeyManager.resolveSpecialGestureEvent(
            .modifierFlagsChanged([.leftShift]),
            hotkey: hotkey,
            state: .idle,
            isSuspended: false
        )
        let targetAdded = HotkeyManager.resolveSpecialGestureEvent(
            .modifierFlagsChanged([.leftShift, .rightCommand]),
            hotkey: hotkey,
            state: extraFirst.state,
            isSuspended: false
        )
        let extraReleased = HotkeyManager.resolveSpecialGestureEvent(
            .modifierFlagsChanged([.rightCommand]),
            hotkey: hotkey,
            state: targetAdded.state,
            isSuspended: false
        )

        XCTAssertEqual(extraFirst, SpecialHotkeyTransition(state: .cancelled, shouldTrigger: false))
        XCTAssertEqual(targetAdded, SpecialHotkeyTransition(state: .cancelled, shouldTrigger: false))
        XCTAssertEqual(extraReleased, SpecialHotkeyTransition(state: .cancelled, shouldTrigger: false))
    }

    func testMultiModifierGestureWaitsForCompleteRelease() {
        let hotkey = sideQualifiedHotkey()

        let partialPress = HotkeyManager.resolveSpecialGestureEvent(
            .modifierFlagsChanged([.leftCommand]),
            hotkey: hotkey,
            state: .idle,
            isSuspended: false
        )
        XCTAssertEqual(partialPress, SpecialHotkeyTransition(state: .idle, shouldTrigger: false))

        let armed = HotkeyManager.resolveSpecialGestureEvent(
            .modifierFlagsChanged([.leftCommand, .rightOption]),
            hotkey: hotkey,
            state: partialPress.state,
            isSuspended: false
        )
        XCTAssertEqual(armed, SpecialHotkeyTransition(state: .armed, action: .began))

        let partialRelease = HotkeyManager.resolveSpecialGestureEvent(
            .modifierFlagsChanged([.leftCommand]),
            hotkey: hotkey,
            state: armed.state,
            isSuspended: false
        )
        XCTAssertEqual(partialRelease, SpecialHotkeyTransition(state: .armed, shouldTrigger: false))

        let completeRelease = HotkeyManager.resolveSpecialGestureEvent(
            .modifierFlagsChanged([]),
            hotkey: hotkey,
            state: partialRelease.state,
            isSuspended: false
        )
        XCTAssertEqual(completeRelease, SpecialHotkeyTransition(state: .idle, shouldTrigger: true))
    }

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

    func testFnKeyDownIsIgnoredButFunctionKeyCancelsGesture() {
        let hotkey = fnHotkey()
        let armed = HotkeyManager.resolveSpecialGestureEvent(
            .modifierFlagsChanged([.function]),
            hotkey: hotkey,
            state: .idle,
            isSuspended: false
        )

        let fnKeyDown = HotkeyManager.resolveSpecialGestureEvent(
            .keyDown(63),
            hotkey: hotkey,
            state: armed.state,
            isSuspended: false
        )
        XCTAssertEqual(fnKeyDown, SpecialHotkeyTransition(state: .armed, shouldTrigger: false))

        let f1KeyDown = HotkeyManager.resolveSpecialGestureEvent(
            .keyDown(122),
            hotkey: hotkey,
            state: fnKeyDown.state,
            isSuspended: false
        )
        XCTAssertEqual(f1KeyDown, SpecialHotkeyTransition(state: .cancelled, shouldTrigger: false))
    }

    func testSystemDefinedFunctionKeyCancelsFnGesture() {
        let hotkey = fnHotkey()
        let armed = HotkeyManager.resolveSpecialGestureEvent(
            .modifierFlagsChanged([.function]),
            hotkey: hotkey,
            state: .idle,
            isSuspended: false
        )

        let systemDefined = HotkeyManager.resolveSpecialGestureEvent(
            .systemDefined,
            hotkey: hotkey,
            state: armed.state,
            isSuspended: false
        )

        XCTAssertEqual(systemDefined, SpecialHotkeyTransition(state: .cancelled, shouldTrigger: false))
    }

    func testSuspensionClearsArmedGesture() {
        let hotkey = fnHotkey()
        let transition = HotkeyManager.resolveSpecialGestureEvent(
            .modifierFlagsChanged([]),
            hotkey: hotkey,
            state: .armed,
            isSuspended: true
        )

        XCTAssertEqual(transition, SpecialHotkeyTransition(state: .idle, action: .cancelled))
    }

    func testCancelledGestureCanArmAgainAfterCompleteRelease() {
        let hotkey = fnHotkey()
        let reset = HotkeyManager.resolveSpecialGestureEvent(
            .modifierFlagsChanged([]),
            hotkey: hotkey,
            state: .cancelled,
            isSuspended: false
        )
        let rearmed = HotkeyManager.resolveSpecialGestureEvent(
            .modifierFlagsChanged([.function]),
            hotkey: hotkey,
            state: reset.state,
            isSuspended: false
        )

        XCTAssertEqual(reset, SpecialHotkeyTransition(state: .idle, action: .cancelled))
        XCTAssertEqual(rearmed, SpecialHotkeyTransition(state: .armed, action: .began))
    }

    func testWrongPhysicalSideDoesNotArmGesture() {
        let transition = HotkeyManager.resolveSpecialGestureEvent(
            .modifierFlagsChanged([.rightCommand, .rightOption]),
            hotkey: sideQualifiedHotkey(),
            state: .idle,
            isSuspended: false
        )

        XCTAssertEqual(transition, SpecialHotkeyTransition(state: .cancelled, shouldTrigger: false))
    }
}
