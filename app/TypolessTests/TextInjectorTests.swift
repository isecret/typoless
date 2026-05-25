import XCTest
@testable import Typoless

final class TextInjectorTests: XCTestCase {
    func testFallbackToAXOnlyWhenSnapshotUnchanged() {
        XCTAssertFalse(
            TextInjector.shouldFallbackToAX(
                beforeValue: nil,
                afterValue: "changed"
            )
        )
        XCTAssertFalse(
            TextInjector.shouldFallbackToAX(
                beforeValue: "before",
                afterValue: nil
            )
        )
        XCTAssertFalse(
            TextInjector.shouldFallbackToAX(
                beforeValue: "before",
                afterValue: "after"
            )
        )
        XCTAssertTrue(
            TextInjector.shouldFallbackToAX(
                beforeValue: "same",
                afterValue: "same"
            )
        )
    }

    func testSlowPasteboardAppsUseStrictVerificationAndLongerRestoreDelay() {
        XCTAssertTrue(TextInjector.debugShouldUseStrictPasteVerification(targetBundleID: "com.apple.Terminal"))
        XCTAssertTrue(TextInjector.debugShouldUseStrictPasteVerification(targetBundleID: "com.googlecode.iterm2"))
        XCTAssertFalse(TextInjector.debugShouldUseStrictPasteVerification(targetBundleID: "com.microsoft.VSCode"))

        XCTAssertEqual(
            TextInjector.debugPasteboardRestoreDelay(targetBundleID: "com.apple.Terminal"),
            800
        )
        XCTAssertEqual(
            TextInjector.debugPasteboardRestoreDelay(targetBundleID: "com.microsoft.VSCode"),
            150
        )
        XCTAssertEqual(
            TextInjector.debugPasteboardRestoreDelay(targetBundleID: nil),
            150
        )
    }

    func testInjectionBreakdownDefaultsToZero() {
        let breakdown = TextInjector.InjectionBreakdown()
        XCTAssertEqual(breakdown.activateTargetMs, 0)
        XCTAssertEqual(breakdown.focusBeforeMs, 0)
        XCTAssertEqual(breakdown.pasteboardWriteMs, 0)
        XCTAssertEqual(breakdown.pasteboardPropagationMs, 0)
        XCTAssertEqual(breakdown.postPasteShortcutMs, 0)
        XCTAssertEqual(breakdown.pasteVerificationMs, 0)
        XCTAssertEqual(breakdown.axFallbackMs, 0)
        XCTAssertEqual(breakdown.pasteboardRestoreMs, 0)
        XCTAssertEqual(breakdown.totalMs, 0)
    }
}
