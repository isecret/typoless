import XCTest
@testable import Typoless

final class LLMProviderTests: XCTestCase {
    func testPolishInputTextIncludesSegmentNoticeForMultipleSegments() {
        let text = LLMProvider.polishInputText(text: "你好世界", segmentCount: 3)

        XCTAssertTrue(text.contains("3 个连续分段转写"))
        XCTAssertTrue(text.hasSuffix("你好世界"))
    }

    func testContextPromptIncludesWeakGuidanceAndSelectedText() {
        let snapshot = WindowContextSnapshot(
            appName: "WeChat",
            bundleID: "com.tencent.xinWeChat",
            windowTitle: "群聊",
            surfaceKind: .chatComposer,
            elementRole: "AXTextField",
            elementSubrole: nil,
            placeholder: "说点什么",
            selectedText: "旧文案",
            surroundingTextBefore: "大家好，",
            surroundingTextAfter: "谢谢",
            nearbyLabels: ["回复", "发送"]
        )

        let prompt = LLMProvider.contextPrompt(snapshot)

        XCTAssertNotNil(prompt)
        XCTAssertTrue(prompt?.contains("只用于帮助消歧") == true)
        XCTAssertTrue(prompt?.contains("selectedText: 旧文案") == true)
        XCTAssertTrue(prompt?.contains("surfaceKind: chatComposer") == true)
        XCTAssertTrue(prompt?.contains("不要直接复制或拼接任何未说出的窗口文本") == true)
    }

    func testTranslateSystemPromptOmitsContextWhenUnavailable() {
        let prompt = LLMProvider.translateSystemPrompt(
            targetLanguage: .english,
            context: nil
        )

        XCTAssertTrue(prompt.contains("请严格翻译成 English"))
        XCTAssertFalse(prompt.contains("当前窗口上下文"))
    }
}
