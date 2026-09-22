import XCTest
@testable import Typoless

@MainActor
final class AppCoordinatorHotkeyTests: XCTestCase {

    func testHotkeyStartsRecordingWhenSessionCanRestart() {
        let restartableStates: [SessionState] = [.idle, .done, .error, .cancelled]

        for state in restartableStates {
            XCTAssertEqual(
                AppCoordinator.hotkeyAction(for: state),
                .startRecording
            )
        }
    }

    func testHotkeyFinishesRecordingWhenAlreadyRecording() {
        XCTAssertEqual(
            AppCoordinator.hotkeyAction(for: .recording),
            .finishRecording
        )
    }

    func testHotkeyDoesNotInterruptProcessingStates() {
        let activeStates: [SessionState] = [.transcribing, .polishing, .injecting]

        for state in activeStates {
            XCTAssertNil(AppCoordinator.hotkeyAction(for: state))
        }
    }

    func testPureModifierPressShowsPendingHUDWithoutStartingRecording() {
        var interaction = AppCoordinator.SpecialHotkeyInteraction()

        let effect = interaction.handle(.began, sessionState: .idle)

        XCTAssertEqual(effect, .showPendingHUD)
        XCTAssertEqual(interaction.pendingAction, .startRecording)
    }

    func testCleanPureModifierReleaseConfirmsPendingRecordingAction() {
        var interaction = AppCoordinator.SpecialHotkeyInteraction()
        _ = interaction.handle(.began, sessionState: .idle)

        let effect = interaction.handle(.confirmed, sessionState: .idle)

        XCTAssertEqual(effect, .perform(.startRecording))
        XCTAssertNil(interaction.pendingAction)
    }

    func testChordCancelsPendingHUDWithoutStartingRecording() {
        var interaction = AppCoordinator.SpecialHotkeyInteraction()
        _ = interaction.handle(.began, sessionState: .idle)

        let effect = interaction.handle(.cancelled, sessionState: .idle)

        XCTAssertEqual(effect, .dismissPendingHUD)
        XCTAssertNil(interaction.pendingAction)
    }

    func testChordDoesNotStopAnExistingRecording() {
        var interaction = AppCoordinator.SpecialHotkeyInteraction()

        XCTAssertEqual(interaction.handle(.began, sessionState: .recording), .none)
        XCTAssertEqual(interaction.pendingAction, .finishRecording)
        XCTAssertEqual(interaction.handle(.cancelled, sessionState: .recording), .none)
        XCTAssertNil(interaction.pendingAction)
    }

    func testCleanPureModifierReleaseStopsAnExistingRecording() {
        var interaction = AppCoordinator.SpecialHotkeyInteraction()
        _ = interaction.handle(.began, sessionState: .recording)

        XCTAssertEqual(
            interaction.handle(.confirmed, sessionState: .recording),
            .perform(.finishRecording)
        )
    }
}
