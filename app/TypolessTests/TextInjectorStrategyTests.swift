import XCTest
@testable import Typoless

final class TextInjectorStrategyTests: XCTestCase {

    func testPrimaryInjectionMethodDefaultsToPasteboard() {
        XCTAssertEqual(
            TextInjector.primaryInjectionMethod(targetBundleID: nil),
            .pasteboardPrimary
        )
        XCTAssertEqual(
            TextInjector.primaryInjectionMethod(targetBundleID: "com.tencent.xinWeChat"),
            .pasteboardPrimary
        )
    }

    func testShouldFallbackToAXWhenReadableValueDoesNotChange() {
        XCTAssertTrue(
            TextInjector.shouldFallbackToAX(
                beforeValue: "unchanged",
                afterValue: "unchanged"
            )
        )
    }

    func testShouldNotFallbackToAXWhenReadableValueChanges() {
        XCTAssertFalse(
            TextInjector.shouldFallbackToAX(
                beforeValue: "before",
                afterValue: "after"
            )
        )
    }

    func testShouldNotFallbackToAXWhenFocusedValueCannotBeRead() {
        XCTAssertFalse(
            TextInjector.shouldFallbackToAX(
                beforeValue: nil,
                afterValue: "after"
            )
        )
        XCTAssertFalse(
            TextInjector.shouldFallbackToAX(
                beforeValue: "before",
                afterValue: nil
            )
        )
    }
}
