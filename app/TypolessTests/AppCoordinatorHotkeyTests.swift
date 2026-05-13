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
}
