import XCTest
@testable import Typoless

final class WindowContextServiceTests: XCTestCase {
    func testBuildSnapshotTrimsAndCapsFields() {
        let candidate = WindowContextCandidate(
            appName: "  WeChat  ",
            bundleID: " com.tencent.xinWeChat ",
            windowTitle: "  聊天窗口  ",
            elementRole: " AXTextField ",
            elementSubrole: "  ",
            placeholder: "  说点什么  ",
            selectedText: String(repeating: "选", count: 240),
            surroundingTextBefore: String(repeating: "前", count: 100),
            surroundingTextAfter: String(repeating: "后", count: 120),
            nearbyLabels: ["  回复  ", "", "回复", " 评论 ", " 发送 ", "额外标签"]
        )

        let result = WindowContextService.buildSnapshot(from: candidate)

        XCTAssertFalse(result.redacted)
        XCTAssertEqual(result.snapshot?.appName, "WeChat")
        XCTAssertEqual(result.snapshot?.bundleID, "com.tencent.xinWeChat")
        XCTAssertEqual(result.snapshot?.windowTitle, "聊天窗口")
        XCTAssertEqual(result.snapshot?.surfaceKind, .chatComposer)
        XCTAssertEqual(result.snapshot?.selectedText?.count, 200)
        XCTAssertEqual(result.snapshot?.surroundingTextBefore?.count, 80)
        XCTAssertEqual(result.snapshot?.surroundingTextAfter?.count, 80)
        XCTAssertEqual(result.snapshot?.nearbyLabels, ["回复", "评论", "发送", "额外标签"])
    }

    func testBuildSnapshotFiltersEmptyValues() {
        let candidate = WindowContextCandidate(
            appName: "   ",
            bundleID: nil,
            windowTitle: "\n",
            elementRole: nil,
            elementSubrole: nil,
            placeholder: " ",
            selectedText: nil,
            surroundingTextBefore: nil,
            surroundingTextAfter: nil,
            nearbyLabels: [" ", "\n"]
        )

        let result = WindowContextService.buildSnapshot(from: candidate)

        XCTAssertNil(result.snapshot)
        XCTAssertFalse(result.redacted)
    }

    func testSensitiveContextRedactsBodyText() {
        let candidate = WindowContextCandidate(
            appName: "1Password",
            bundleID: "com.1password.1password",
            windowTitle: "登录",
            elementRole: "AXTextField",
            elementSubrole: "AXSecureTextField",
            placeholder: "Password",
            selectedText: "hunter2",
            surroundingTextBefore: "prefix",
            surroundingTextAfter: "suffix",
            nearbyLabels: ["Master Password", "Sign In"]
        )

        let result = WindowContextService.buildSnapshot(from: candidate)

        XCTAssertTrue(result.redacted)
        XCTAssertEqual(result.snapshot?.appName, "1Password")
        XCTAssertEqual(result.snapshot?.bundleID, "com.1password.1password")
        XCTAssertNil(result.snapshot?.placeholder)
        XCTAssertNil(result.snapshot?.selectedText)
        XCTAssertNil(result.snapshot?.surroundingTextBefore)
        XCTAssertNil(result.snapshot?.surroundingTextAfter)
        XCTAssertEqual(result.snapshot?.nearbyLabels, [])
    }

    func testCaptureContextResultMarksRedactedEvent() async {
        let service = WindowContextService { _, _ in
            WindowContextCandidate(
                appName: "Terminal",
                bundleID: "com.apple.Terminal",
                windowTitle: "zsh",
                elementRole: "AXTextArea",
                elementSubrole: nil,
                placeholder: nil,
                selectedText: "secret",
                surroundingTextBefore: "before",
                surroundingTextAfter: "after",
                nearbyLabels: ["Shell"]
            )
        }

        let result = await service.captureContextResult(targetPID: nil, targetBundleID: nil)

        XCTAssertEqual(result.event, .redacted)
        XCTAssertNil(result.snapshot?.selectedText)
    }
}
