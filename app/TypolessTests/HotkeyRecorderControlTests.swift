import XCTest
@testable import Typoless

final class HotkeyRecorderControlTests: XCTestCase {
    func testModifierPreviewDoesNotRegressWhenReleasingPartOfLargestCombination() {
        let initial = HotkeyRecorderControl.resolveModifierPreviewState(
            pressed: [.leftControl, .leftShift],
            previousLargest: []
        )
        XCTAssertEqual(initial.preview, [.leftControl, .leftShift])
        XCTAssertEqual(initial.largest, [.leftControl, .leftShift])

        let expanded = HotkeyRecorderControl.resolveModifierPreviewState(
            pressed: [.leftControl, .leftShift, .rightCommand],
            previousLargest: initial.largest
        )
        XCTAssertEqual(expanded.preview, [.leftControl, .leftShift, .rightCommand])
        XCTAssertEqual(expanded.largest, [.leftControl, .leftShift, .rightCommand])

        let partialRelease = HotkeyRecorderControl.resolveModifierPreviewState(
            pressed: [.leftControl, .leftShift],
            previousLargest: expanded.largest
        )
        XCTAssertEqual(partialRelease.preview, [.leftControl, .leftShift, .rightCommand])
        XCTAssertEqual(partialRelease.largest, [.leftControl, .leftShift, .rightCommand])
    }
}
