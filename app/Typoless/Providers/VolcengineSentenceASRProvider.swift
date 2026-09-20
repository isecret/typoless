import Foundation

final class VolcengineSentenceASRProvider: ASRProvider, CloudASRValidating, @unchecked Sendable {
    private static let timeout: TimeInterval = 15
    private static let recognizeURL = URL(string: "https://openspeech.bytedance.com/api/v3/auc/bigmodel/recognize/flash")!
    private static let resourceID = "volc.bigasr.auc_turbo"

    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func recognize(audioData: Data, timeout: TimeInterval? = nil) async throws -> TranscriptResult {
        guard !apiKey.isEmpty else {
            throw TypolessError.cloudASRConfigurationIncomplete
        }

        let effectiveTimeout = timeout ?? Self.timeout
        let base64Audio = audioData.base64EncodedString()

        let requestBody: [String: Any] = [
            "user": [
                "uid": "typoless",
            ],
            "audio": [
                "data": base64Audio,
            ],
            "request": [
                "model_name": "bigmodel",
            ],
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
        let endpoint = "\(Self.recognizeURL.host ?? "unknown")\(Self.recognizeURL.path)"

        CloudASRRequestLogger.requestPrepared(
            CloudASRRequestMetrics(
                provider: "volcengine",
                endpoint: endpoint,
                transport: "json_base64_wav",
                audioBytes: audioData.count,
                uploadBytes: bodyData.count,
                timeoutMs: Int(effectiveTimeout * 1000),
                base64Bytes: base64Audio.utf8.count,
                frameCount: nil,
                minFrameBytes: nil,
                maxFrameBytes: nil,
                extra: nil
            )
        )

        var request = URLRequest(url: Self.recognizeURL)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.timeoutInterval = effectiveTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue(Self.resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue("-1", forHTTPHeaderField: "X-Api-Sequence")

        let startTime = Date()
        let (responseData, response): (Data, URLResponse)
        do {
            (responseData, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            CloudASRRequestLogger.requestFailed(
                provider: "volcengine",
                endpoint: endpoint,
                phase: "network",
                message: error.localizedDescription
            )
            throw TypolessError.cloudASRNetworkFailure(message: error.localizedDescription)
        } catch {
            CloudASRRequestLogger.requestFailed(
                provider: "volcengine",
                endpoint: endpoint,
                phase: "network",
                message: error.localizedDescription
            )
            throw TypolessError.cloudASRNetworkFailure(message: error.localizedDescription)
        }

        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
        let httpResponse = response as? HTTPURLResponse
        let httpStatus = httpResponse?.statusCode
        let statusCode = httpResponse?.value(forHTTPHeaderField: "X-Api-Status-Code") ?? ""
        let statusMessage = httpResponse?.value(forHTTPHeaderField: "X-Api-Message") ?? ""
        let logID = httpResponse?.value(forHTTPHeaderField: "X-Tt-Logid")

        if let httpStatus = httpResponse?.statusCode, !(200...299).contains(httpStatus) {
            if httpStatus == 401 || httpStatus == 403 {
                CloudASRRequestLogger.requestFailed(
                    provider: "volcengine",
                    endpoint: endpoint,
                    phase: "http",
                    statusCode: httpStatus,
                    message: "authentication_failed"
                )
                throw TypolessError.cloudASRAuthenticationFailure
            }
            let body = String(data: responseData, encoding: .utf8) ?? ""
            CloudASRRequestLogger.requestFailed(
                provider: "volcengine",
                endpoint: endpoint,
                phase: "http",
                statusCode: httpStatus,
                message: body
            )
            throw TypolessError.cloudASRNetworkFailure(message: "HTTP \(httpStatus): \(body)")
        }

        switch statusCode {
        case "", "20000000":
            break
        case "20000003", "45000002":
            CloudASRRequestLogger.requestFailed(
                provider: "volcengine",
                endpoint: endpoint,
                phase: "api",
                statusCode: httpStatus,
                message: statusMessage
            )
            throw TypolessError.cloudASREmptyResponse
        case "401", "403":
            CloudASRRequestLogger.requestFailed(
                provider: "volcengine",
                endpoint: endpoint,
                phase: "api",
                statusCode: httpStatus,
                message: statusMessage
            )
            throw TypolessError.cloudASRAuthenticationFailure
        default:
            CloudASRRequestLogger.requestFailed(
                provider: "volcengine",
                endpoint: endpoint,
                phase: "api",
                statusCode: httpStatus,
                message: "[\(statusCode)] \(statusMessage)"
            )
            throw TypolessError.cloudASRInvalidResponse(detail: "[\(statusCode)] \(statusMessage)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let result = json["result"] as? [String: Any] else {
            CloudASRRequestLogger.requestFailed(
                provider: "volcengine",
                endpoint: endpoint,
                phase: "parse",
                statusCode: httpStatus,
                message: "invalid_json"
            )
            throw TypolessError.cloudASRInvalidResponse(detail: "火山引擎 ASR 响应 JSON 无法解析")
        }

        guard let text = (result["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            CloudASRRequestLogger.requestFailed(
                provider: "volcengine",
                endpoint: endpoint,
                phase: "parse",
                statusCode: httpStatus,
                message: "empty_text"
            )
            throw TypolessError.cloudASREmptyResponse
        }

        let transcript = TranscriptResult(text: text, requestId: logID, durationMs: durationMs)
        CloudASRRequestLogger.requestCompleted(
            provider: "volcengine",
            endpoint: endpoint,
            durationMs: durationMs,
            responseBytes: responseData.count,
            statusCode: httpStatus,
            requestID: transcript.requestId
        )
        return transcript
    }

    func validateCredentials() async throws {
        let silentAudio = WAVAudioEncoder.encodePCM16(pcmData: Data(repeating: 0, count: 3200), sampleRate: 16_000, channels: 1)
        _ = try await recognize(audioData: silentAudio, timeout: 15)
    }
}
