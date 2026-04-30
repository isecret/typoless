import XCTest
@testable import Typoless

final class StructuredPolishParserTests: XCTestCase {

    // MARK: - plain_text 场景

    func testPlainTextParsesSuccessfully() {
        let json = """
        {"mode":"plain_text","text":"今天天气不错。","items":null,"salutation":null,"body":null,"closing":null,"correction_applied":false}
        """

        let result = StructuredPolishParser.parse(content: json)
        guard case .structured(let response) = result else {
            XCTFail("Expected structured result")
            return
        }
        XCTAssertEqual(response.mode, .plainText)
        XCTAssertEqual(response.text, "今天天气不错。")
        XCTAssertFalse(response.correctionApplied)
    }

    // MARK: - list 场景

    func testListParsesSuccessfully() {
        let json = """
        {"mode":"list","text":"1. 苹果\\n2. 香蕉\\n3. 橙子","items":["苹果","香蕉","橙子"],"salutation":null,"body":null,"closing":null,"correction_applied":false}
        """

        let result = StructuredPolishParser.parse(content: json)
        guard case .structured(let response) = result else {
            XCTFail("Expected structured result")
            return
        }
        XCTAssertEqual(response.mode, .list)
        XCTAssertEqual(response.items, ["苹果", "香蕉", "橙子"])
    }

    func testListWithEmptyItemsFallsBack() {
        let json = """
        {"mode":"list","text":"没有列表","items":[],"salutation":null,"body":null,"closing":null,"correction_applied":false}
        """

        let result = StructuredPolishParser.parse(content: json)
        guard case .invalidStructure(let fallback) = result else {
            XCTFail("Expected invalidStructure result, got \(result)")
            return
        }
        XCTAssertEqual(fallback, "没有列表")
    }

    // MARK: - message 场景

    func testMessageParsesSuccessfully() {
        let json = """
        {"mode":"message","text":"张总，明天上午十点开会，请准时。谢谢","salutation":"张总，","body":["明天上午十点开会，请准时。"],"closing":"谢谢","correction_applied":false}
        """

        let result = StructuredPolishParser.parse(content: json)
        guard case .structured(let response) = result else {
            XCTFail("Expected structured result")
            return
        }
        XCTAssertEqual(response.mode, .message)
        XCTAssertEqual(response.salutation, "张总，")
        XCTAssertEqual(response.body, ["明天上午十点开会，请准时。"])
        XCTAssertEqual(response.closing, "谢谢")
    }

    func testMessageWithEmptyBodyFallsBack() {
        let json = """
        {"mode":"message","text":"你好","salutation":"你好","body":[],"closing":null,"correction_applied":false}
        """

        let result = StructuredPolishParser.parse(content: json)
        guard case .invalidStructure(let fallback) = result else {
            XCTFail("Expected invalidStructure")
            return
        }
        XCTAssertEqual(fallback, "你好")
    }

    // MARK: - 自我修正

    func testCorrectionApplied() {
        let json = """
        {"mode":"plain_text","text":"我要去北京。","items":null,"salutation":null,"body":null,"closing":null,"correction_applied":true}
        """

        let result = StructuredPolishParser.parse(content: json)
        guard case .structured(let response) = result else {
            XCTFail("Expected structured result")
            return
        }
        XCTAssertTrue(response.correctionApplied)
        XCTAssertEqual(response.text, "我要去北京。")
    }

    // MARK: - 非法 JSON 回退

    func testInvalidJSONFallsBackToPlainText() {
        let content = "这是一段普通文本，不是JSON"

        let result = StructuredPolishParser.parse(content: content)
        guard case .plainText(let text) = result else {
            XCTFail("Expected plainText fallback")
            return
        }
        XCTAssertEqual(text, "这是一段普通文本，不是JSON")
    }

    func testMalformedJSONWithTextFieldExtractsText() {
        let content = """
        {"mode":"plain_text","text":"提取这段文字","items":invalid}
        """

        let result = StructuredPolishParser.parse(content: content)
        // Should fall back but try to extract text field
        switch result {
        case .plainText(let text):
            // Either extracts text or uses raw content
            XCTAssertFalse(text.isEmpty)
        case .invalidStructure(let fallback):
            XCTAssertFalse(fallback.isEmpty)
        case .structured:
            XCTFail("Should not parse successfully")
        }
    }

    func testEmptyContentReturnsPlainText() {
        let content = "   "

        let result = StructuredPolishParser.parse(content: content)
        guard case .plainText(let text) = result else {
            XCTFail("Expected plainText")
            return
        }
        XCTAssertTrue(text.isEmpty)
    }

    // MARK: - Code fence 包裹

    func testCodeFenceWrappedJSON() {
        let content = """
        ```json
        {"mode":"plain_text","text":"从代码块中提取。","items":null,"salutation":null,"body":null,"closing":null,"correction_applied":false}
        ```
        """

        let result = StructuredPolishParser.parse(content: content)
        guard case .structured(let response) = result else {
            XCTFail("Expected structured result")
            return
        }
        XCTAssertEqual(response.text, "从代码块中提取。")
    }

    // MARK: - 缺字段兼容

    func testMissingCorrectionAppliedDefaultsToFalse() {
        let json = """
        {"mode":"plain_text","text":"没有 correction_applied 字段"}
        """

        let result = StructuredPolishParser.parse(content: json)
        guard case .structured(let response) = result else {
            XCTFail("Expected structured result")
            return
        }
        XCTAssertFalse(response.correctionApplied)
    }
}
