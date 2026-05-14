import XCTest
@testable import Typoless

@MainActor
final class HUDFeedbackControllerTests: XCTestCase {
    private final class MockFeedbackSoundPlayer: FeedbackSoundPlaying {
        var startCount = 0
        var stopCount = 0

        func playStart() {
            startCount += 1
        }

        func playStop() {
            stopCount += 1
        }
    }

    func testFailureEventPresentsHUDWhenHidden() {
        let controller = HUDFeedbackController()

        XCTAssertEqual(controller.hudState, .hidden)
        XCTAssertFalse(controller.isHUDPresented)

        controller.handleEvent(.processingFailed(.permissionDenied))

        XCTAssertEqual(controller.hudState, .failure(.permissionDenied))
        XCTAssertTrue(controller.isHUDPresented)
    }

    func testFailureEventStopsRecordingPresentationSideEffects() {
        let controller = HUDFeedbackController()

        controller.handleEvent(.recordingStarted)
        XCTAssertEqual(controller.hudState, .recording)
        XCTAssertTrue(controller.isHUDPresented)

        controller.handleEvent(.processingFailed(.permissionDenied))

        XCTAssertEqual(controller.hudState, .failure(.permissionDenied))
        XCTAssertTrue(controller.isHUDPresented)
        XCTAssertEqual(controller.barHeights, Array(repeating: 1, count: 7))
        XCTAssertEqual(controller.barOpacities, Array(repeating: 0.28, count: 7))
    }

    func testInteractionSoundDisabledSkipsStartAndStopPlayback() {
        let soundPlayer = MockFeedbackSoundPlayer()
        let controller = HUDFeedbackController(soundPlayer: soundPlayer)
        controller.isInteractionSoundEnabled = { false }

        controller.handleEvent(.startSoundCue)
        controller.handleEvent(.recordingStopped)

        XCTAssertEqual(soundPlayer.startCount, 0)
        XCTAssertEqual(soundPlayer.stopCount, 0)
    }

    func testInteractionSoundEnabledPlaysStartAndStopSounds() {
        let soundPlayer = MockFeedbackSoundPlayer()
        let controller = HUDFeedbackController(soundPlayer: soundPlayer)
        controller.isInteractionSoundEnabled = { true }

        controller.handleEvent(.startSoundCue)
        controller.handleEvent(.recordingStopped)

        XCTAssertEqual(soundPlayer.startCount, 1)
        XCTAssertEqual(soundPlayer.stopCount, 1)
    }
}
