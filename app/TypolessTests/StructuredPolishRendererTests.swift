import XCTest
@testable import Typoless

final class StructuredPolishRendererTests: XCTestCase {

    // MARK: - plain_text 渲染

    func testPlainTextRendering() {
        let response = makeLLMResponse(mode: .plainText, text: "今天天气不错。")
        let rendered = StructuredPolishRenderer.render(response: response)
        XCTAssertEqual(rendered, "今天天气不错。")
    }

    func testPlainTextTrimsWhitespace() {
        let response = makeLLMResponse(mode: .plainText, text: "  有空格  ")
        let rendered = StructuredPolishRenderer.render(response: response)
        XCTAssertEqual(rendered, "有空格")
    }

    // MARK: - list 渲染

    func testListRendering() {
        let response = makeLLMResponse(
            mode: .list,
            text: "1. 买菜\n2. 做饭\n3. 洗碗",
            items: ["买菜", "做饭", "洗碗"]
        )
        let rendered = StructuredPolishRenderer.render(response: response)
        XCTAssertEqual(rendered, "1. 买菜\n2. 做饭\n3. 洗碗")
    }

    func testListWithEmptyItemsFallsBackToText() {
        let response = makeLLMResponse(
            mode: .list,
            text: "没有真正的列表",
            items: []
        )
        let rendered = StructuredPolishRenderer.render(response: response)
        XCTAssertEqual(rendered, "没有真正的列表")
    }

    func testListWithNilItemsFallsBackToText() {
        let response = makeLLMResponse(
            mode: .list,
            text: "也不是列表",
            items: nil
        )
        let rendered = StructuredPolishRenderer.render(response: response)
        XCTAssertEqual(rendered, "也不是列表")
    }

    // MARK: - message 渲染

    func testMessageFullRendering() {
        let response = makeLLMResponse(
            mode: .message,
            text: "张总，明天十点开会。谢谢",
            salutation: "张总，",
            body: ["明天十点开会。"],
            closing: "谢谢"
        )
        let rendered = StructuredPolishRenderer.render(response: response)
        XCTAssertEqual(rendered, "张总，\n明天十点开会。\n谢谢")
    }

    func testMessageWithoutSalutation() {
        let response = makeLLMResponse(
            mode: .message,
            text: "明天十点开会。谢谢",
            salutation: nil,
            body: ["明天十点开会。"],
            closing: "谢谢"
        )
        let rendered = StructuredPolishRenderer.render(response: response)
        XCTAssertEqual(rendered, "明天十点开会。\n谢谢")
    }

    func testMessageWithoutClosing() {
        let response = makeLLMResponse(
            mode: .message,
            text: "老王，下午记得带文件。",
            salutation: "老王，",
            body: ["下午记得带文件。"],
            closing: nil
        )
        let rendered = StructuredPolishRenderer.render(response: response)
        XCTAssertEqual(rendered, "老王，\n下午记得带文件。")
    }

    func testMessageWithMultipleBodyParagraphs() {
        let response = makeLLMResponse(
            mode: .message,
            text: "李总，关于下周的安排有两点。第一，周一全体会议。第二，周三提交报告。请知悉",
            salutation: "李总，",
            body: ["关于下周的安排有两点。", "第一，周一全体会议。", "第二，周三提交报告。"],
            closing: "请知悉"
        )
        let rendered = StructuredPolishRenderer.render(response: response)
        XCTAssertEqual(rendered, "李总，\n关于下周的安排有两点。\n第一，周一全体会议。\n第二，周三提交报告。\n请知悉")
    }

    func testMessageWithEmptyBodyFallsBackToText() {
        let response = makeLLMResponse(
            mode: .message,
            text: "直接用text",
            salutation: "你好",
            body: [],
            closing: nil
        )
        let rendered = StructuredPolishRenderer.render(response: response)
        XCTAssertEqual(rendered, "直接用text")
    }

    // MARK: - Helpers

    private func makeLLMResponse(
        mode: PolishMode,
        text: String,
        items: [String]? = nil,
        salutation: String? = nil,
        body: [String]? = nil,
        closing: String? = nil,
        correctionApplied: Bool = false
    ) -> LLMStructuredResponse {
        // We need to encode and decode since LLMStructuredResponse only has Decodable
        let dict: [String: Any?] = [
            "mode": mode.rawValue,
            "text": text,
            "items": items,
            "salutation": salutation,
            "body": body,
            "closing": closing,
            "correction_applied": correctionApplied
        ]
        let filtered = dict.compactMapValues { $0 }
        let data = try! JSONSerialization.data(withJSONObject: filtered)
        return try! JSONDecoder().decode(LLMStructuredResponse.self, from: data)
    }
}
