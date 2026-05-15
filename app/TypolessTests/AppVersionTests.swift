import XCTest
@testable import Typoless

final class AppVersionTests: XCTestCase {

    func testParsesReleaseTagsWithLeadingV() {
        let version = AppVersion("v1.2.3")

        XCTAssertEqual(version?.rawValue, "1.2.3")
    }

    func testComparesVersionsNumerically() {
        XCTAssertLessThan(AppVersion("1.2.9")!, AppVersion("1.2.10")!)
        XCTAssertLessThan(AppVersion("1.2")!, AppVersion("1.2.1")!)
        XCTAssertEqual(AppVersion("1.2")!, AppVersion("1.2.0")!)
    }

    func testRejectsInvalidVersions() {
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("v1.beta"))
        XCTAssertNil(AppVersion("release-1"))
    }
}
