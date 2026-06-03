import SwiftUI
import XCTest
@testable import Typoless

final class ASRSettingsViewStatusTests: XCTestCase {
    func testInitialPresentationUsesVerifiedStateAsReady() {
        let presentation = ASRCloudStatusPresentation.initial(
            isComplete: true,
            persistedState: .verified,
            errorMessage: nil
        )

        XCTAssertEqual(presentation, .ready)
        XCTAssertEqual(presentation.text, "已就绪")
    }

    func testInitialPresentationUsesFailedStateWhenErrorExists() {
        let presentation = ASRCloudStatusPresentation.initial(
            isComplete: true,
            persistedState: .failed,
            errorMessage: "认证失败"
        )

        XCTAssertEqual(presentation, .failed)
        XCTAssertTrue(presentation.showsErrorMessage)
    }

    func testInitialPresentationFallsBackToNotReadyWithoutCompleteConfig() {
        let presentation = ASRCloudStatusPresentation.initial(
            isComplete: false,
            persistedState: .verified,
            errorMessage: nil
        )

        XCTAssertEqual(presentation, .notReady)
    }

    func testCurrentSessionPresentationTreatsCheckingAsReady() {
        let presentation = ASRCloudStatusPresentation.currentSession(
            isComplete: true,
            serviceStatus: .checking,
            errorMessage: nil
        )

        XCTAssertEqual(presentation, .ready)
    }

    func testCurrentSessionPresentationUsesFailedStateWhenErrorExists() {
        let presentation = ASRCloudStatusPresentation.currentSession(
            isComplete: true,
            serviceStatus: .failed,
            errorMessage: "网络错误"
        )

        XCTAssertEqual(presentation, .failed)
        XCTAssertEqual(presentation.systemImage, "xmark.circle.fill")
    }
}
