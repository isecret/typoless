import XCTest
@testable import Typoless

@MainActor
final class HotkeyManagerRegistrationTests: XCTestCase {
    private final class CallbackRecorder {
        var specialActions: [SpecialHotkeyGestureAction] = []
        var standardPressCount = 0
    }

    private let rightCommand = HotkeyCombo.special(
        modifiers: [HotkeyModifierSpec(key: .command, side: .right)]
    )

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

    func testSuspendingManagerClearsArmedSpecialGesture() {
        let manager = HotkeyManager()
        _ = manager.consumeSpecialGestureEvent(
            .modifierFlagsChanged([.rightCommand]),
            hotkey: rightCommand
        )

        manager.setSuspended(true)
        manager.setSuspended(false)

        XCTAssertFalse(
            manager.consumeSpecialGestureEvent(.modifierFlagsChanged([]), hotkey: rightCommand)
        )
    }

    func testUnregisteringManagerClearsArmedSpecialGesture() {
        let manager = HotkeyManager()
        _ = manager.consumeSpecialGestureEvent(
            .modifierFlagsChanged([.rightCommand]),
            hotkey: rightCommand
        )

        manager.unregister()

        XCTAssertFalse(
            manager.consumeSpecialGestureEvent(.modifierFlagsChanged([]), hotkey: rightCommand)
        )
    }

    func testFailedReplacementAndRollbackClearArmedSpecialGesture() {
        let manager = HotkeyManager()
        let incoming = HotkeyCombo.special(
            modifiers: [HotkeyModifierSpec(key: .function)]
        )
        manager.testInstallHandler = { combo in
            combo == incoming ? .failure("无法注册该快捷键，可能已被系统占用。") : .success
        }
        XCTAssertEqual(manager.register(hotkey: rightCommand), .success)
        _ = manager.consumeSpecialGestureEvent(
            .modifierFlagsChanged([.rightCommand]),
            hotkey: rightCommand
        )

        _ = manager.replace(with: incoming)

        XCTAssertFalse(
            manager.consumeSpecialGestureEvent(.modifierFlagsChanged([]), hotkey: rightCommand)
        )
    }

    func testSpecialGesturePublishesPhasesWithoutUsingStandardPressCallback() async {
        let manager = HotkeyManager()
        let recorder = CallbackRecorder()
        manager.onSpecialGestureAction = { action in
            recorder.specialActions.append(action)
        }
        manager.onKeyDown = {
            recorder.standardPressCount += 1
        }

        _ = manager.consumeSpecialGestureEvent(
            .modifierFlagsChanged([.rightCommand]),
            hotkey: rightCommand
        )
        await Task.yield()
        _ = manager.consumeSpecialGestureEvent(
            .modifierFlagsChanged([]),
            hotkey: rightCommand
        )
        await Task.yield()

        XCTAssertEqual(recorder.specialActions, [.began, .confirmed])
        XCTAssertEqual(recorder.standardPressCount, 0)
    }

    func testSuspendingManagerPublishesPendingGestureCancellation() async {
        let manager = HotkeyManager()
        let recorder = CallbackRecorder()
        manager.onSpecialGestureAction = { action in
            recorder.specialActions.append(action)
        }

        _ = manager.consumeSpecialGestureEvent(
            .modifierFlagsChanged([.rightCommand]),
            hotkey: rightCommand
        )
        await Task.yield()
        manager.setSuspended(true)
        await Task.yield()

        XCTAssertEqual(recorder.specialActions, [.began, .cancelled])
    }
}
