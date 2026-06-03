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

    func testListRenderingPreservesIntro() {
        let response = makeLLMResponse(
            mode: .list,
            text: "我明天要出差，提醒我带一些东西：\n1. 身份证\n2. 充电宝",
            intro: "我明天要出差，提醒我带一些东西：",
            items: ["身份证", "充电宝"]
        )
        let rendered = StructuredPolishRenderer.render(response: response)
        XCTAssertEqual(rendered, "我明天要出差，提醒我带一些东西：\n1. 身份证\n2. 充电宝")
    }

    func testListRenderingPreservesOutro() {
        let response = makeLLMResponse(
            mode: .list,
            text: "我明天要出差，提醒我带一些东西：\n1. 身份证\n2. 充电宝\n另外明天航班是早上九点的，记得提醒我出门。",
            intro: "我明天要出差，提醒我带一些东西：",
            items: ["身份证", "充电宝"],
            outro: "另外明天航班是早上九点的，记得提醒我出门。"
        )
        let rendered = StructuredPolishRenderer.render(response: response)
        XCTAssertEqual(rendered, "我明天要出差，提醒我带一些东西：\n1. 身份证\n2. 充电宝\n另外明天航班是早上九点的，记得提醒我出门。")
    }

    func testListRenderingSupportsOutroWithoutIntro() {
        let response = makeLLMResponse(
            mode: .list,
            text: "1. 身份证\n2. 充电宝\n另外明天航班是早上九点的，记得提醒我出门。",
            items: ["身份证", "充电宝"],
            outro: "另外明天航班是早上九点的，记得提醒我出门。"
        )
        let rendered = StructuredPolishRenderer.render(response: response)
        XCTAssertEqual(rendered, "1. 身份证\n2. 充电宝\n另外明天航班是早上九点的，记得提醒我出门。")
    }

    func testListRenderingAddsColonToIntroWhenMissing() {
        let response = makeLLMResponse(
            mode: .list,
            text: "我明天要出差，提醒我带一些东西：\n1. 身份证",
            intro: "我明天要出差，提醒我带一些东西",
            items: ["身份证"]
        )
        let rendered = StructuredPolishRenderer.render(response: response)
        XCTAssertEqual(rendered, "我明天要出差，提醒我带一些东西：\n1. 身份证")
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

    // MARK: - sanitizer

    func testFillerWordSanitizerRemovesLeadingPureFillers() {
        let rendered = FillerWordSanitizer.sanitize("嗯我想确认一下明天的会议。")
        XCTAssertEqual(rendered, "我想确认一下明天的会议。")
    }

    func testFillerWordSanitizerRemovesLeadingFillerPhrase() {
        let rendered = FillerWordSanitizer.sanitize("然后就是我们先对一下。")
        XCTAssertEqual(rendered, "我们先对一下。")
    }

    func testFillerWordSanitizerPreservesSequentialThen() {
        let rendered = FillerWordSanitizer.sanitize("先保存文件，然后再退出。")
        XCTAssertEqual(rendered, "先保存文件，然后再退出。")
    }

    func testFillerWordSanitizerPreservesSemanticThisAndThat() {
        let rendered = FillerWordSanitizer.sanitize("这个事情我来处理。")
        XCTAssertEqual(rendered, "这个事情我来处理。")
    }

    // MARK: - prompt

    func testLLMProviderSystemPromptIncludesFillerRules() {
        let prompt = LLMProvider.systemPrompt(terms: [])
        XCTAssertTrue(prompt.contains("然后\" 仅在充当口头衔接"))
        XCTAssertTrue(prompt.contains("保留 \"然后\""))
        XCTAssertTrue(prompt.contains("然后就是"))
    }

    // MARK: - Helpers

    private func makeLLMResponse(
        mode: PolishMode,
        text: String,
        intro: String? = nil,
        items: [String]? = nil,
        outro: String? = nil,
        correctionApplied: Bool = false
    ) -> LLMStructuredResponse {
        // We need to encode and decode since LLMStructuredResponse only has Decodable
        let dict: [String: Any?] = [
            "mode": mode.rawValue,
            "text": text,
            "intro": intro,
            "items": items,
            "outro": outro,
            "correction_applied": correctionApplied
        ]
        let filtered = dict.compactMapValues { $0 }
        let data = try! JSONSerialization.data(withJSONObject: filtered)
        return try! JSONDecoder().decode(LLMStructuredResponse.self, from: data)
    }
}
