import Foundation

protocol XiaomiMiMoASRHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: XiaomiMiMoASRHTTPClient {}

final class XiaomiMiMoASRProvider: ASRProvider, CloudASRValidating, @unchecked Sendable {
    static let defaultBaseURL = URL(string: "https://api.xiaomimimo.com/v1")!
    static let tokenPlanBaseURL = URL(string: "https://token-plan-cn.xiaomimimo.com/v1")!
    static let recognizeURL = chatCompletionsURL(for: defaultBaseURL)
    static let tokenPlanRecognizeURL = chatCompletionsURL(for: tokenPlanBaseURL)
    static let modelID = "mimo-v2.5-asr"
    static let defaultLanguage = "auto"

    private static let defaultTimeout: TimeInterval = 15

    private let apiKey: String
    private let language: String
    private let recognizeURL: URL
    private let httpClient: any XiaomiMiMoASRHTTPClient

    init(
        apiKey: String,
        language: String = Self.defaultLanguage,
        baseURL: URL = Self.defaultBaseURL,
        httpClient: any XiaomiMiMoASRHTTPClient = URLSession.shared
    ) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.language = XiaomiMiMoASRConfig.normalizedLanguage(language)
        self.recognizeURL = Self.chatCompletionsURL(for: baseURL)
        self.httpClient = httpClient
    }

    static func chatCompletionsURL(for baseURL: URL) -> URL {
        baseURL
            .deletingTrailingSlashPathComponent()
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")
    }

    func recognize(audioData: Data, timeout: TimeInterval? = nil) async throws -> TranscriptResult {
        guard !apiKey.isEmpty else {
            throw TypolessError.cloudASRConfigurationIncomplete
        }

        let requestBody = XiaomiMiMoASRRequest(
            model: Self.modelID,
            messages: [
                XiaomiMiMoASRMessage(
                    role: "user",
                    content: [
                        XiaomiMiMoASRContent(
                            type: "input_audio",
                            inputAudio: XiaomiMiMoASRInputAudio(
                                data: "data:audio/wav;base64,\(audioData.base64EncodedString())"
                            )
                        ),
                    ]
                ),
            ],
            asrOptions: XiaomiMiMoASROptions(language: language),
            stream: false
        )

        let bodyData = try JSONEncoder().encode(requestBody)

        var request = URLRequest(url: recognizeURL)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.timeoutInterval = timeout ?? Self.defaultTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let startTime = Date()
        let responseData: Data
        let response: URLResponse

        do {
            (responseData, response) = try await httpClient.data(for: request)
        } catch let error as URLError {
            throw TypolessError.cloudASRNetworkFailure(message: error.localizedDescription)
        } catch {
            throw TypolessError.cloudASRNetworkFailure(message: error.localizedDescription)
        }

        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
        let httpResponse = response as? HTTPURLResponse
        if let httpStatus = httpResponse?.statusCode, !(200...299).contains(httpStatus) {
            if httpStatus == 401 || httpStatus == 403 {
                throw TypolessError.cloudASRAuthenticationFailure
            }
            throw TypolessError.cloudASRNetworkFailure(message: "HTTP \(httpStatus)")
        }

        let decodedResponse: XiaomiMiMoASRResponse
        do {
            decodedResponse = try JSONDecoder().decode(XiaomiMiMoASRResponse.self, from: responseData)
        } catch {
            throw TypolessError.cloudASRInvalidResponse(detail: "小米 MiMo ASR 响应 JSON 无法解析")
        }

        guard let text = decodedResponse.choices.first?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw TypolessError.cloudASRInvalidResponse(detail: "小米 MiMo ASR 响应缺少识别文本")
        }

        guard !text.isEmpty else {
            throw TypolessError.cloudASREmptyResponse
        }

        return TranscriptResult(text: text, requestId: decodedResponse.id, durationMs: durationMs)
    }

    func validateCredentials() async throws {
        let silentAudio = WAVAudioEncoder.encodePCM16(
            pcmData: Data(repeating: 0, count: 3200),
            sampleRate: 16_000,
            channels: 1
        )
        _ = try await recognize(audioData: silentAudio, timeout: 15)
    }
}

private extension URL {
    func deletingTrailingSlashPathComponent() -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        let currentPath = components?.path ?? self.path
        if currentPath.count > 1, currentPath.hasSuffix("/") {
            components?.path = String(currentPath.dropLast())
            return components?.url ?? self
        }
        return self
    }
}

private struct XiaomiMiMoASRRequest: Encodable {
    let model: String
    let messages: [XiaomiMiMoASRMessage]
    let asrOptions: XiaomiMiMoASROptions
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case asrOptions = "asr_options"
        case stream
    }
}

private struct XiaomiMiMoASRMessage: Encodable {
    let role: String
    let content: [XiaomiMiMoASRContent]
}

private struct XiaomiMiMoASRContent: Encodable {
    let type: String
    let inputAudio: XiaomiMiMoASRInputAudio

    enum CodingKeys: String, CodingKey {
        case type
        case inputAudio = "input_audio"
    }
}

private struct XiaomiMiMoASRInputAudio: Encodable {
    let data: String
}

private struct XiaomiMiMoASROptions: Encodable {
    let language: String
}

private struct XiaomiMiMoASRResponse: Decodable {
    let id: String?
    let choices: [XiaomiMiMoASRChoice]
}

private struct XiaomiMiMoASRChoice: Decodable {
    let message: XiaomiMiMoASRResponseMessage
}

private struct XiaomiMiMoASRResponseMessage: Decodable {
    let content: String
}
