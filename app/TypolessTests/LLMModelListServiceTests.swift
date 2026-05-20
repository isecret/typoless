import XCTest
@testable import Typoless

final class LLMModelListServiceTests: XCTestCase {

    @MainActor
    func testIncompleteInputDoesNotRunFetcher() async {
        let counter = ModelListCounter()
        let service = LLMModelListService(
            fetcher: { _ in
                await counter.increment()
                return ["gpt-4o-mini"]
            }
        )

        service.load(
            LLMModelListInput(
                baseURL: "",
                apiKey: "test-key"
            )
        )

        XCTAssertEqual(service.status, .incomplete)
        XCTAssertTrue(service.models.isEmpty)
        XCTAssertNil(service.lastErrorMessage)
        let count = await counter.currentValue()
        XCTAssertEqual(count, 0)
    }

    @MainActor
    func testSuccessfulLoadPublishesModels() async {
        let service = LLMModelListService(
            fetcher: { _ in
                try await Task.sleep(for: .milliseconds(20))
                return ["gpt-4o", "gpt-4o-mini"]
            }
        )

        service.load(makeInput())

        XCTAssertEqual(service.status, .loading)
        await waitUntil { service.status == .loaded }
        XCTAssertEqual(service.models, ["gpt-4o", "gpt-4o-mini"])
        XCTAssertNil(service.lastErrorMessage)
    }

    @MainActor
    func testLoadFailureKeepsManualInputAvailable() async {
        let service = LLMModelListService(
            fetcher: { _ in
                throw TypolessError.invalidLLMConfiguration(detail: "当前服务不支持模型列表，可手动输入 Model")
            }
        )

        service.load(makeInput())

        await waitUntil { service.status == .unavailable }
        XCTAssertTrue(service.models.isEmpty)
        XCTAssertEqual(service.lastErrorMessage, "LLM 配置异常：当前服务不支持模型列表，可手动输入 Model")
    }

    @MainActor
    func testLatestLoadWinsOverCancelledRequest() async {
        let service = LLMModelListService(
            fetcher: { input in
                if input.baseURL == "https://first.example.com/v1" {
                    try await Task.sleep(for: .milliseconds(150))
                    return ["old-model"]
                }
                return ["new-model"]
            }
        )

        service.load(makeInput(baseURL: "https://first.example.com/v1"))
        service.load(makeInput(baseURL: "https://second.example.com/v1"))

        await waitUntil { service.status == .loaded }
        XCTAssertEqual(service.models, ["new-model"])
    }

    private func makeInput(baseURL: String = "https://example.com/v1") -> LLMModelListInput {
        LLMModelListInput(
            baseURL: baseURL,
            apiKey: "test-key"
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

private actor ModelListCounter {
    private var value = 0

    func increment() {
        value += 1
    }

    func currentValue() -> Int {
        value
    }
}
