import XCTest
@testable import Typoless

final class XiaomiMiMoASRProviderTests: XCTestCase {
    func testRecognizeBuildsChatCompletionsRequestAndParsesText() async throws {
        let audioData = Data([1, 2, 3, 4])
        let client = StubXiaomiMiMoHTTPClient(
            responseData: Data(#"{"id":"req-1","choices":[{"message":{"content":" 你好世界 "}}]}"#.utf8),
            statusCode: 200
        )
        let provider = XiaomiMiMoASRProvider(apiKey: "mimo-key", httpClient: client)

        let result = try await provider.recognize(audioData: audioData, timeout: 23)

        XCTAssertEqual(result.text, "你好世界")
        XCTAssertEqual(result.requestId, "req-1")

        let lastRequest = await client.lastRequest
        let request = try XCTUnwrap(lastRequest)
        XCTAssertEqual(request.url, XiaomiMiMoASRProvider.recognizeURL)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 23)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer mimo-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["model"] as? String, XiaomiMiMoASRProvider.modelID)
        XCTAssertEqual(json?["stream"] as? Bool, false)

        let asrOptions = json?["asr_options"] as? [String: Any]
        XCTAssertEqual(asrOptions?["language"] as? String, "auto")

        let messages = try XCTUnwrap(json?["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "input_audio")
        let inputAudio = try XCTUnwrap(content.first?["input_audio"] as? [String: Any])
        XCTAssertEqual(inputAudio["data"] as? String, "data:audio/wav;base64,\(audioData.base64EncodedString())")
    }

    func testRecognizeUsesTokenPlanRequestURL() async throws {
        let client = StubXiaomiMiMoHTTPClient(
            responseData: Data(#"{"choices":[{"message":{"content":"text"}}]}"#.utf8),
            statusCode: 200
        )
        let provider = XiaomiMiMoASRProvider(
            apiKey: "mimo-key",
            baseURL: XiaomiMiMoASRProvider.tokenPlanBaseURL,
            httpClient: client
        )

        _ = try await provider.recognize(audioData: Data([1]), timeout: nil)

        let lastRequest = await client.lastRequest
        let request = try XCTUnwrap(lastRequest)
        XCTAssertEqual(request.url, XiaomiMiMoASRProvider.tokenPlanRecognizeURL)
    }

    func testChatCompletionsURLNormalizesTrailingSlash() throws {
        let withoutSlash = try XCTUnwrap(URL(string: "https://token-plan-cn.xiaomimimo.com/v1"))
        let withSlash = try XCTUnwrap(URL(string: "https://token-plan-cn.xiaomimimo.com/v1/"))
        let expected = try XCTUnwrap(URL(string: "https://token-plan-cn.xiaomimimo.com/v1/chat/completions"))

        XCTAssertEqual(XiaomiMiMoASRProvider.chatCompletionsURL(for: withoutSlash), expected)
        XCTAssertEqual(XiaomiMiMoASRProvider.chatCompletionsURL(for: withSlash), expected)
    }

    func testRecognizeUsesAutoLanguageByDefault() async throws {
        let client = StubXiaomiMiMoHTTPClient(
            responseData: Data(#"{"choices":[{"message":{"content":"text"}}]}"#.utf8),
            statusCode: 200
        )
        let provider = XiaomiMiMoASRProvider(apiKey: "mimo-key", httpClient: client)

        _ = try await provider.recognize(audioData: Data([1]), timeout: nil)

        let lastRequest = await client.lastRequest
        let request = try XCTUnwrap(lastRequest)
        let body = try XCTUnwrap(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let asrOptions = json?["asr_options"] as? [String: Any]
        XCTAssertEqual(asrOptions?["language"] as? String, "auto")
    }

    func testRecognizeThrowsConfigurationIncompleteWhenAPIKeyMissing() async {
        let client = StubXiaomiMiMoHTTPClient(
            responseData: Data(#"{"choices":[{"message":{"content":"text"}}]}"#.utf8),
            statusCode: 200
        )
        let provider = XiaomiMiMoASRProvider(apiKey: " ", httpClient: client)

        do {
            _ = try await provider.recognize(audioData: Data([1]), timeout: nil)
            XCTFail("Expected configuration error")
        } catch let error as TypolessError {
            XCTAssertEqual(error, .cloudASRConfigurationIncomplete)
            let lastRequest = await client.lastRequest
            XCTAssertNil(lastRequest)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRecognizeMapsAuthenticationFailure() async {
        let client = StubXiaomiMiMoHTTPClient(responseData: Data(), statusCode: 401)
        let provider = XiaomiMiMoASRProvider(apiKey: "mimo-key", httpClient: client)

        await XCTAssertThrowsTypolessError(
            { try await provider.recognize(audioData: Data([1]), timeout: nil) },
            expected: .cloudASRAuthenticationFailure
        )
    }

    func testRecognizeMapsEmptyContent() async {
        let client = StubXiaomiMiMoHTTPClient(
            responseData: Data(#"{"choices":[{"message":{"content":"   "}}]}"#.utf8),
            statusCode: 200
        )
        let provider = XiaomiMiMoASRProvider(apiKey: "mimo-key", httpClient: client)

        await XCTAssertThrowsTypolessError(
            { try await provider.recognize(audioData: Data([1]), timeout: nil) },
            expected: .cloudASREmptyResponse
        )
    }

    func testRecognizeMapsNetworkFailure() async {
        let client = StubXiaomiMiMoHTTPClient(error: URLError(.timedOut))
        let provider = XiaomiMiMoASRProvider(apiKey: "mimo-key", httpClient: client)

        do {
            _ = try await provider.recognize(audioData: Data([1]), timeout: nil)
            XCTFail("Expected network failure")
        } catch let error as TypolessError {
            if case .cloudASRNetworkFailure = error {
                return
            }
            XCTFail("Unexpected TypolessError: \(error)")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private actor StubXiaomiMiMoHTTPClient: XiaomiMiMoASRHTTPClient {
    private let responseData: Data
    private let statusCode: Int
    private let error: Error?
    private var capturedRequest: URLRequest?

    init(responseData: Data = Data(), statusCode: Int = 200, error: Error? = nil) {
        self.responseData = responseData
        self.statusCode = statusCode
        self.error = error
    }

    var lastRequest: URLRequest? {
        capturedRequest
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        capturedRequest = request

        if let error {
            throw error
        }

        let response = HTTPURLResponse(
            url: request.url ?? XiaomiMiMoASRProvider.recognizeURL,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }
}

private func XCTAssertThrowsTypolessError<T>(
    _ expression: () async throws -> T,
    expected: TypolessError,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected \(expected)", file: file, line: line)
    } catch let error as TypolessError {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("Unexpected error: \(error)", file: file, line: line)
    }
}
