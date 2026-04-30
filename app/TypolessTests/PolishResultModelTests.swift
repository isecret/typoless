import XCTest
@testable import Typoless

final class PolishResultModelTests: XCTestCase {

    // MARK: - PolishMode

    func testPolishModeRawValues() {
        XCTAssertEqual(PolishMode.plainText.rawValue, "plain_text")
        XCTAssertEqual(PolishMode.list.rawValue, "list")
        XCTAssertEqual(PolishMode.message.rawValue, "message")
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
            items: nil, salutation: nil, body: nil, closing: nil,
            correctionApplied: false
        )
        XCTAssertTrue(result.isValid)
    }

    func testListValidWithItems() {
        let result = StructuredPolishResult(
            mode: .list,
            items: ["a", "b"], salutation: nil, body: nil, closing: nil,
            correctionApplied: false
        )
        XCTAssertTrue(result.isValid)
    }

    func testListInvalidWithEmptyItems() {
        let result = StructuredPolishResult(
            mode: .list,
            items: [], salutation: nil, body: nil, closing: nil,
            correctionApplied: false
        )
        XCTAssertFalse(result.isValid)
    }

    func testListInvalidWithNilItems() {
        let result = StructuredPolishResult(
            mode: .list,
            items: nil, salutation: nil, body: nil, closing: nil,
            correctionApplied: false
        )
        XCTAssertFalse(result.isValid)
    }

    func testMessageValidWithBody() {
        let result = StructuredPolishResult(
            mode: .message,
            items: nil, salutation: "你好", body: ["正文"], closing: nil,
            correctionApplied: false
        )
        XCTAssertTrue(result.isValid)
    }

    func testMessageInvalidWithEmptyBody() {
        let result = StructuredPolishResult(
            mode: .message,
            items: nil, salutation: "你好", body: [], closing: nil,
            correctionApplied: false
        )
        XCTAssertFalse(result.isValid)
    }

    func testMessageInvalidWithNilBody() {
        let result = StructuredPolishResult(
            mode: .message,
            items: nil, salutation: nil, body: nil, closing: nil,
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
            items: nil, salutation: nil, body: nil, closing: nil,
            correctionApplied: false
        )
        let result = PolishResult(text: "hello", source: .llm, structured: structured)
        XCTAssertNotNil(result.structured)
        XCTAssertEqual(result.structured?.mode, .plainText)
    }
}
