import XCTest
@testable import Typoless

final class LLMModelProviderTests: XCTestCase {

    func testFetchModelsParsesAndSortsUniqueModelIDs() async throws {
        let recorder = RequestRecorder()
        let provider = LLMModelProvider(
            baseURL: "https://example.com/v1/",
            apiKey: "test-key",
            dataLoader: { request in
                await recorder.record(request)

                let data = Data("""
                {
                  "object": "list",
                  "data": [
                    { "id": "gpt-4o-mini" },
                    { "id": "gpt-4o" },
                    { "id": "gpt-4o-mini" },
                    { "id": " " }
                  ]
                }
                """.utf8)
                return (data, Self.httpResponse(statusCode: 200))
            }
        )

        let models = try await provider.fetchModels()
        let recordedRequest = await recorder.lastRequest

        XCTAssertEqual(recordedRequest?.url?.absoluteString, "https://example.com/v1/models")
        XCTAssertEqual(recordedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(models, ["gpt-4o", "gpt-4o-mini"])
    }

    func testFetchModelsMapsUnsupportedEndpointToManualFallbackMessage() async {
        let provider = LLMModelProvider(
            baseURL: "https://example.com/v1",
            apiKey: "test-key",
            dataLoader: { _ in
                (Data(), Self.httpResponse(statusCode: 404))
            }
        )

        do {
            _ = try await provider.fetchModels()
            XCTFail("Expected unsupported endpoint error")
        } catch let error as TypolessError {
            XCTAssertEqual(
                error,
                .invalidLLMConfiguration(detail: "当前服务不支持模型列表，可手动输入 Model")
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchModelsRejectsEmptyModelList() async {
        let provider = LLMModelProvider(
            baseURL: "https://example.com/v1",
            apiKey: "test-key",
            dataLoader: { _ in
                let data = Data(#"{ "data": [] }"#.utf8)
                return (data, Self.httpResponse(statusCode: 200))
            }
        )

        do {
            _ = try await provider.fetchModels()
            XCTFail("Expected empty model list error")
        } catch let error as TypolessError {
            XCTAssertEqual(error, .llmNetworkFailure(message: "模型列表为空"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private static func httpResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.com/v1/models")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}

private actor RequestRecorder {
    private(set) var lastRequest: URLRequest?

    func record(_ request: URLRequest) {
        lastRequest = request
    }
}
