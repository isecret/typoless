import XCTest
@testable import Typoless

final class LLMValidationServiceTests: XCTestCase {

    @MainActor
    func testIncompleteInputDoesNotRunValidator() async {
        let counter = Counter()
        let service = LLMValidationService(
            validator: { _, _ in
                await counter.increment()
            }
        )

        service.validate(
            LLMValidationInput(
                baseURL: "",
                apiKey: "key",
                model: "gpt-4o-mini",
                thinkingDisabled: false
            )
        )

        XCTAssertEqual(service.status, .incomplete)
        XCTAssertNil(service.lastErrorMessage)
        let count = await counter.currentValue()
        XCTAssertEqual(count, 0)
    }

    @MainActor
    func testSuccessfulValidationTransitionsToReady() async {
        let service = LLMValidationService(
            validator: { _, _ in
                try await Task.sleep(for: .milliseconds(20))
            }
        )

        service.validate(makeInput())

        XCTAssertEqual(service.status, .checking)
        await waitUntil { service.status == .ready }
        XCTAssertNil(service.lastErrorMessage)
    }

    @MainActor
    func testValidationFailureExposesUserFacingError() async {
        let service = LLMValidationService(
            validator: { _, _ in
                throw TypolessError.invalidLLMConfiguration(detail: "模型不存在或 URL 错误")
            }
        )

        service.validate(makeInput())

        await waitUntil { service.status == .failed }
        XCTAssertEqual(service.lastErrorMessage, "LLM 配置异常：模型不存在或 URL 错误")
    }

    @MainActor
    func testLatestValidationWinsOverCancelledRequest() async {
        let service = LLMValidationService(
            validator: { input, _ in
                if input.model == "first-model" {
                    try await Task.sleep(for: .milliseconds(150))
                    throw TypolessError.llmNetworkFailure(message: "old request should be cancelled")
                }
            }
        )

        service.validate(makeInput(model: "first-model"))
        service.validate(makeInput(model: "second-model"))

        await waitUntil { service.status == .ready }
        XCTAssertNil(service.lastErrorMessage)
    }

    @MainActor
    func testThinkingUnsupportedCallbackCanBeTriggered() async {
        let counter = Counter()
        let service = LLMValidationService(
            onThinkingUnsupported: {
                Task {
                    await counter.increment()
                }
            },
            validator: { _, onThinkingUnsupported in
                await onThinkingUnsupported()
            }
        )

        service.validate(makeInput())

        await waitUntil { service.status == .ready }
        let start = ContinuousClock.now
        while ContinuousClock.now - start < .seconds(1) {
            if await counter.currentValue() == 1 {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for callback")
    }

    private func makeInput(model: String = "gpt-4o-mini") -> LLMValidationInput {
        LLMValidationInput(
            baseURL: "https://example.com/v1",
            apiKey: "test-key",
            model: model,
            thinkingDisabled: false
        )
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async {
        let start = ContinuousClock.now
        while ContinuousClock.now - start < timeout {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for condition")
    }
}

private actor Counter {
    private var value = 0

    func increment() {
        value += 1
    }

    func currentValue() -> Int {
        value
    }
}
