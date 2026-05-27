import XCTest
@testable import Typoless

@MainActor
final class HUDFeedbackControllerTests: XCTestCase {
    private final class MockFeedbackSoundPlayer: FeedbackSoundPlaying {
        var startCount = 0
        var stopCount = 0
        var keepAliveEnabledValues: [Bool] = []
        var delayedStartParameters: (maxWaitMs: Int, minimumWaitMs: Int, pollIntervalMs: Int, retryDelayMs: Int)?

        func playStart() {
            startCount += 1
        }

        func playStop() {
            stopCount += 1
        }

        func setSilentKeepAliveEnabled(_ enabled: Bool) {
            keepAliveEnabledValues.append(enabled)
        }

        func playStartAfterOutputStabilizes(
            maxWaitMs: Int,
            minimumWaitMs: Int,
            pollIntervalMs: Int,
            retryDelayMs: Int
        ) async {
            delayedStartParameters = (maxWaitMs, minimumWaitMs, pollIntervalMs, retryDelayMs)
            startCount += 1
        }
    }

    private final class DelayedFeedbackSoundPlayer: FeedbackSoundPlaying {
        var delayedStartCount = 0
        var stopCount = 0
        var didEnterDelayedStart = false

        func playStart() {
            delayedStartCount += 1
        }

        func playStop() {
            stopCount += 1
        }

        func playStartAfterOutputStabilizes(
            maxWaitMs: Int,
            minimumWaitMs: Int,
            pollIntervalMs: Int,
            retryDelayMs: Int
        ) async {
            didEnterDelayedStart = true
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            delayedStartCount += 1
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

    func testInteractionSoundEnabledPlaysStartAndStopSounds() async {
        let soundPlayer = MockFeedbackSoundPlayer()
        let controller = HUDFeedbackController(soundPlayer: soundPlayer)
        controller.isInteractionSoundEnabled = { true }

        controller.handleEvent(.startSoundCue)
        await waitForStartSound(soundPlayer)
        controller.handleEvent(.recordingStopped)

        XCTAssertEqual(soundPlayer.startCount, 1)
        XCTAssertEqual(soundPlayer.stopCount, 1)
        XCTAssertEqual(soundPlayer.delayedStartParameters?.maxWaitMs, 2_200)
        XCTAssertEqual(soundPlayer.delayedStartParameters?.minimumWaitMs, 600)
        XCTAssertEqual(soundPlayer.delayedStartParameters?.pollIntervalMs, 100)
        XCTAssertEqual(soundPlayer.delayedStartParameters?.retryDelayMs, 200)
    }

    func testInteractionSoundKeepAliveForwardsEnabledState() {
        let soundPlayer = MockFeedbackSoundPlayer()
        let controller = HUDFeedbackController(soundPlayer: soundPlayer)

        controller.setInteractionSoundKeepAliveEnabled(true)
        controller.setInteractionSoundKeepAliveEnabled(false)

        XCTAssertEqual(soundPlayer.keepAliveEnabledValues, [true, false])
    }

    func testStoppingRecordingCancelsPendingStartSound() async {
        let soundPlayer = DelayedFeedbackSoundPlayer()
        let controller = HUDFeedbackController(soundPlayer: soundPlayer)
        controller.isInteractionSoundEnabled = { true }

        controller.handleEvent(.startSoundCue)
        await waitForDelayedStartToBegin(soundPlayer)
        controller.handleEvent(.recordingStopped)
        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(soundPlayer.delayedStartCount, 0)
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
        let controller = HUDFeedbackController(modeCueDuration: .milliseconds(10))

        controller.handleEvent(.recordingStarted)
        controller.handleEvent(.modeSwitched(.translate))
        controller.handleEvent(.modeSwitched(.polish))

        XCTAssertEqual(controller.hudState, .recording)
        XCTAssertEqual(controller.modeCueLabel, "DICTATE")

        await waitForModeCueToClear(controller)

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

    private func waitForModeCueToClear(_ controller: HUDFeedbackController) async {
        for _ in 0..<20 {
            if controller.modeCueLabel == nil { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private func waitForStartSound(_ soundPlayer: MockFeedbackSoundPlayer) async {
        for _ in 0..<20 {
            if soundPlayer.startCount > 0 { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private func waitForDelayedStartToBegin(_ soundPlayer: DelayedFeedbackSoundPlayer) async {
        for _ in 0..<20 {
            if soundPlayer.didEnterDelayedStart { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }
}
