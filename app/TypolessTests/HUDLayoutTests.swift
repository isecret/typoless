import XCTest
@testable import Typoless

final class HUDLayoutTests: XCTestCase {
    func testHUDScaleIsOnePointTwo() {
        XCTAssertEqual(HUDLayout.scale, 1.2)
    }

    func testScaledCoreDimensionsMatchCurrentHUDScale() {
        XCTAssertEqual(HUDLayout.hiddenWidth, 115.2, accuracy: 0.001)
        XCTAssertEqual(HUDLayout.activeWidth, 105.6, accuracy: 0.001)
        XCTAssertEqual(HUDLayout.resultWidth, 86.4, accuracy: 0.001)
        XCTAssertEqual(HUDLayout.capsuleHeight, 31.2, accuracy: 0.001)
        XCTAssertEqual(HUDLayout.iconSize, 16.8, accuracy: 0.001)
        XCTAssertEqual(HUDLayout.buttonSize, 21.6, accuracy: 0.001)
        XCTAssertEqual(HUDLayout.waveformWidth, 40.8, accuracy: 0.001)
    }

    func testNoticeWidthShrinksForShortTermsAndExpandsForLongerTerms() {
        let shortWidth = HUDLayout.noticeWidth(for: "朴邻")
        let longWidth = HUDLayout.noticeWidth(for: "客户成功…")

        XCTAssertEqual(shortWidth, 86.4, accuracy: 0.001)
        XCTAssertGreaterThan(longWidth, shortWidth)
    }

    func testHUDWindowSizeTracksScaledLayout() {
        XCTAssertEqual(HUDLayout.windowSize.width, 240, accuracy: 0.001)
        XCTAssertEqual(HUDLayout.windowSize.height, 52.8, accuracy: 0.001)
    }

    func testHUDColorsAreOpaqueAndCentralized() {
        let colors = [
            HUDLayout.capsuleBackgroundColor,
            HUDLayout.capsuleInnerStrokeColor,
            HUDLayout.capsuleOuterStrokeColor,
            HUDLayout.primaryForegroundColor,
            HUDLayout.secondaryForegroundColor,
            HUDLayout.waveformColor,
            HUDLayout.cancelButtonBackgroundColor,
            HUDLayout.cancelButtonStrokeColor,
            HUDLayout.confirmButtonBackgroundColor,
            HUDLayout.confirmButtonForegroundColor,
            HUDLayout.thinkingBaseTextColor,
            HUDLayout.thinkingHighlightTextColor
        ]

        for color in colors {
            XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.001)
        }
    }
}
