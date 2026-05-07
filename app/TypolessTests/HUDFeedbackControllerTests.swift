import XCTest
@testable import Typoless

@MainActor
final class HUDFeedbackControllerTests: XCTestCase {

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
}
