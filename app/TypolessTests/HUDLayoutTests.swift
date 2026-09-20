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

    func testHUDWindowCanContainAllScaledCapsuleWidths() {
        let widths = [
            HUDLayout.hiddenWidth,
            HUDLayout.activeWidth,
            HUDLayout.resultWidth,
            HUDLayout.noticeWidth(for: "客户成功…"),
            HUDLayout.noticeWidth(for: "迁移平台…")
        ]

        for width in widths {
            XCTAssertLessThanOrEqual(width, HUDLayout.windowSize.width)
        }
        XCTAssertLessThanOrEqual(HUDLayout.capsuleHeight, HUDLayout.windowSize.height)
    }

    func testHUDBottomReservedHeightUsesOnlyBottomOccupiedSpace() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)

        let bottomDockVisibleFrame = NSRect(x: 0, y: 64, width: 1440, height: 836)
        XCTAssertEqual(
            HUDWindow.bottomReservedHeight(
                screenFrame: screenFrame,
                visibleFrame: bottomDockVisibleFrame
            ),
            64,
            accuracy: 0.001
        )

        let sideDockVisibleFrame = NSRect(x: 96, y: 0, width: 1344, height: 900)
        XCTAssertEqual(
            HUDWindow.bottomReservedHeight(
                screenFrame: screenFrame,
                visibleFrame: sideDockVisibleFrame
            ),
            0,
            accuracy: 0.001
        )
    }

    func testHUDFrameOriginKeepsSmallBaseMarginWhenBottomIsUnoccupied() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 860)

        let origin = HUDWindow.frameOrigin(
            windowSize: HUDLayout.windowSize,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin.x, 600, accuracy: 0.001)
        XCTAssertEqual(origin.y, HUDLayout.baseBottomMargin, accuracy: 0.001)
    }

    func testHUDFrameOriginAddsBottomDockHeightToBaseMargin() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleFrame = NSRect(x: 0, y: 72, width: 1440, height: 788)

        let origin = HUDWindow.frameOrigin(
            windowSize: HUDLayout.windowSize,
            screenFrame: screenFrame,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin.y, HUDLayout.baseBottomMargin + 72, accuracy: 0.001)
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

    func testAllHUDStatesShareOneOpaqueCapsuleBaseColor() {
        XCTAssertEqual(HUDLayout.capsuleBackgroundColor.alphaComponent, 1, accuracy: 0.001)
        XCTAssertEqual(HUDLayout.capsuleBackgroundColor, HUDLayout.sharedCapsuleBackgroundColor)
    }
}
