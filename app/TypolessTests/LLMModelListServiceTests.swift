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
    func testInitialFailureIsReusedUntilExplicitRetry() async {
        let counter = ModelListCounter()
        let service = LLMModelListService(
            fetcher: { _ in
                await counter.increment()
                throw TypolessError.llmNetworkFailure(message: "private response body")
            }
        )

        service.load(makeInput())
        await waitUntil { service.status == .unavailable }
        service.load(makeInput())

        XCTAssertEqual(service.status, .unavailable)
        XCTAssertEqual(service.lastErrorMessage, "LLM 请求失败，请检查配置或网络")
        var count = await counter.currentValue()
        XCTAssertEqual(count, 1)

        service.load(makeInput(), force: true)
        await waitUntilAsync { await counter.currentValue() == 2 }
        count = await counter.currentValue()
        XCTAssertEqual(count, 2)
    }

    @MainActor
    func testUnknownFailureDoesNotExposeUnderlyingResponseOrCredential() async {
        let service = LLMModelListService(
            fetcher: { _ in
                throw NSError(
                    domain: "ModelListTests",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "response body contains test-key"
                    ]
                )
            }
        )

        service.load(makeInput())

        await waitUntil { service.status == .unavailable }
        XCTAssertEqual(service.lastErrorMessage, "无法获取模型列表，可手动输入 Model")
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

    @MainActor
    func testCompletedLoadIsReusedWithoutReturningToLoadingOrRefetching() async {
        let counter = ModelListCounter()
        let service = LLMModelListService(
            fetcher: { _ in
                await counter.increment()
                return ["cached-model"]
            }
        )

        service.load(makeInput())
        await waitUntil { service.status == .loaded }
        service.load(makeInput())

        XCTAssertEqual(service.status, .loaded)
        XCTAssertEqual(service.models, ["cached-model"])
        let count = await counter.currentValue()
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testDuplicateLoadWhileRequestIsRunningDoesNotStartSecondTask() async {
        let counter = ModelListCounter()
        let service = LLMModelListService(
            fetcher: { _ in
                await counter.increment()
                try await Task.sleep(for: .milliseconds(80))
                return ["one-model"]
            }
        )

        service.load(makeInput())
        service.load(makeInput())

        await waitUntil { service.status == .loaded }
        let count = await counter.currentValue()
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testChangingBaseURLOrAPIKeyUsesIndependentCacheEntries() async {
        let counter = ModelListCounter()
        let service = LLMModelListService(
            fetcher: { input in
                await counter.increment()
                return [input.baseURL + ":" + input.apiKey]
            }
        )

        service.load(makeInput())
        await waitUntil { service.status == .loaded }
        service.load(makeInput(baseURL: "https://other.example.com/v1"))
        await waitUntil { service.models == ["https://other.example.com/v1:test-key"] }
        service.load(makeInput(apiKey: "other-key"))
        await waitUntil { service.models == ["https://example.com/v1:other-key"] }

        service.load(makeInput())

        XCTAssertEqual(service.status, .loaded)
        XCTAssertEqual(service.models, ["https://example.com/v1:test-key"])

        let count = await counter.currentValue()
        XCTAssertEqual(count, 3)
    }

    @MainActor
    func testReturningToCachedIdentityInvalidatesDifferentPendingRequest() async {
        let counter = ModelListCounter()
        let service = LLMModelListService(
            fetcher: { input in
                await counter.increment()
                if input.baseURL == "https://pending.example.com/v1" {
                    try await Task.sleep(for: .milliseconds(120))
                    return ["pending-model"]
                }
                return ["cached-model"]
            }
        )

        service.load(makeInput())
        await waitUntil { service.models == ["cached-model"] }

        service.load(makeInput(baseURL: "https://pending.example.com/v1"))
        await waitUntilAsync { await counter.currentValue() == 2 }
        service.load(makeInput())

        XCTAssertEqual(service.status, .loaded)
        XCTAssertEqual(service.models, ["cached-model"])
        try? await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(service.models, ["cached-model"])
    }

    @MainActor
    func testExpiredCacheRefreshesSilentlyAndReplacesModels() async {
        let counter = ModelListCounter()
        var now = ContinuousClock.now
        let service = LLMModelListService(
            cacheTTL: .seconds(60),
            now: { now },
            fetcher: { _ in
                let attempt = await counter.incrementAndGet()
                try await Task.sleep(for: .milliseconds(20))
                return attempt == 1 ? ["cached-model"] : ["refreshed-model"]
            }
        )

        service.load(makeInput())
        await waitUntil { service.models == ["cached-model"] }
        now = now.advanced(by: .seconds(61))

        service.load(makeInput())

        XCTAssertEqual(service.status, .loaded)
        XCTAssertEqual(service.models, ["cached-model"])
        await waitUntil { service.models == ["refreshed-model"] }
        let count = await counter.currentValue()
        XCTAssertEqual(count, 2)
    }

    @MainActor
    func testFailedSilentRefreshPreservesCachedModels() async {
        let counter = ModelListCounter()
        var now = ContinuousClock.now
        let service = LLMModelListService(
            cacheTTL: .seconds(60),
            now: { now },
            fetcher: { _ in
                let attempt = await counter.incrementAndGet()
                if attempt == 1 {
                    return ["cached-model"]
                }
                throw TypolessError.llmNetworkFailure(message: "private response body")
            }
        )

        service.load(makeInput())
        await waitUntil { service.models == ["cached-model"] }
        now = now.advanced(by: .seconds(61))

        service.load(makeInput())
        await waitUntil { service.lastErrorMessage != nil }

        XCTAssertEqual(service.status, .loaded)
        XCTAssertEqual(service.models, ["cached-model"])
        XCTAssertEqual(service.lastErrorMessage, "LLM 请求失败，请检查配置或网络")

        service.load(makeInput())
        let count = await counter.currentValue()
        XCTAssertEqual(count, 2)
    }

    private func makeInput(
        baseURL: String = "https://example.com/v1",
        apiKey: String = "test-key"
    ) -> LLMModelListInput {
        LLMModelListInput(
            baseURL: baseURL,
            apiKey: apiKey
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

    @MainActor
    private func waitUntilAsync(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () async -> Bool
    ) async {
        let start = ContinuousClock.now
        while ContinuousClock.now - start < timeout {
            if await condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for asynchronous condition")
    }
}

private actor ModelListCounter {
    private var value = 0

    func increment() {
        value += 1
    }

    func incrementAndGet() -> Int {
        value += 1
        return value
    }

    func currentValue() -> Int {
        value
    }
}
