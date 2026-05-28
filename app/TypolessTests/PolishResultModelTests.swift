import XCTest
@testable import Typoless

final class PolishResultModelTests: XCTestCase {

    // MARK: - PolishMode

    func testPolishModeRawValues() {
        XCTAssertEqual(PolishMode.plainText.rawValue, "plain_text")
        XCTAssertEqual(PolishMode.list.rawValue, "list")
    }

    func testPolishModeDecodable() throws {
        let json = #""plain_text""#.data(using: .utf8)!
        let mode = try JSONDecoder().decode(PolishMode.self, from: json)
        XCTAssertEqual(mode, .plainText)
    }

    // MARK: - StructuredPolishResult validation

    func testPlainTextAlwaysValid() {
        let result = StructuredPolishResult(
            mode: .plainText,
            intro: nil,
            items: nil, outro: nil,
            correctionApplied: false
        )
        XCTAssertTrue(result.isValid)
    }

    func testListValidWithItems() {
        let result = StructuredPolishResult(
            mode: .list,
            intro: "出差要带的东西",
            items: ["a", "b"], outro: "另外明天九点出门。",
            correctionApplied: false
        )
        XCTAssertTrue(result.isValid)
    }

    func testListInvalidWithEmptyItems() {
        let result = StructuredPolishResult(
            mode: .list,
            intro: "出差要带的东西",
            items: [], outro: "另外明天九点出门。",
            correctionApplied: false
        )
        XCTAssertFalse(result.isValid)
    }

    func testListInvalidWithNilItems() {
        let result = StructuredPolishResult(
            mode: .list,
            intro: nil,
            items: nil, outro: nil,
            correctionApplied: false
        )
        XCTAssertFalse(result.isValid)
    }

    // MARK: - PolishResult backward compatibility

    func testPolishResultWithoutStructured() {
        let result = PolishResult(text: "hello", source: .llm)
        XCTAssertEqual(result.text, "hello")
        XCTAssertNil(result.structured)
    }

    func testPolishResultWithStructured() {
        let structured = StructuredPolishResult(
            mode: .plainText,
            intro: nil,
            items: nil, outro: nil,
            correctionApplied: false
        )
        let result = PolishResult(text: "hello", source: .llm, structured: structured)
        XCTAssertNotNil(result.structured)
        XCTAssertEqual(result.structured?.mode, .plainText)
    }
}
