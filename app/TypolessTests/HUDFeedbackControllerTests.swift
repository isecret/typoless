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

    func testModeSwitchCueKeepsRecordingState() {
        let controller = HUDFeedbackController()

        controller.handleEvent(.recordingStarted)
        controller.handleEvent(.modeSwitched(.translate))

        XCTAssertEqual(controller.hudState, .recording)
        XCTAssertEqual(controller.modeCueLabel, "TRANSLATE")
    }

    func testConsecutiveModeSwitchCueShowsLatestLabel() async {
        let controller = HUDFeedbackController()

        controller.handleEvent(.recordingStarted)
        controller.handleEvent(.modeSwitched(.translate))
        controller.handleEvent(.modeSwitched(.polish))

        XCTAssertEqual(controller.hudState, .recording)
        XCTAssertEqual(controller.modeCueLabel, "DICTATE")

        try? await Task.sleep(for: .milliseconds(700))

        XCTAssertEqual(controller.hudState, .recording)
        XCTAssertNil(controller.modeCueLabel)
    }

    func testStoppingRecordingClearsModeCue() {
        let controller = HUDFeedbackController()

        controller.handleEvent(.recordingStarted)
        controller.handleEvent(.modeSwitched(.translate))
        controller.handleEvent(.recordingStopped)

        XCTAssertEqual(controller.hudState, .processing)
        XCTAssertNil(controller.modeCueLabel)
    }
}
