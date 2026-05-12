import Foundation

final class VolcengineSentenceASRProvider: ASRProvider, @unchecked Sendable {
    private static let timeout: TimeInterval = 15
    private static let recognizeURL = URL(string: "https://openspeech.bytedance.com/api/v3/auc/bigmodel/recognize/flash")!
    private static let resourceID = "volc.bigasr.auc_turbo"

    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func recognize(audioData: Data) async throws -> TranscriptResult {
        guard !apiKey.isEmpty else {
            throw TypolessError.cloudASRConfigurationIncomplete
        }

        let requestBody: [String: Any] = [
            "user": [
                "uid": "typoless",
            ],
            "audio": [
                "data": audioData.base64EncodedString(),
            ],
            "request": [
                "model_name": "bigmodel",
            ],
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)

        var request = URLRequest(url: Self.recognizeURL)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.timeoutInterval = Self.timeout
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
            throw TypolessError.cloudASRNetworkFailure(message: error.localizedDescription)
        } catch {
            throw TypolessError.cloudASRNetworkFailure(message: error.localizedDescription)
        }

        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.value(forHTTPHeaderField: "X-Api-Status-Code") ?? ""
        let statusMessage = httpResponse?.value(forHTTPHeaderField: "X-Api-Message") ?? ""
        let logID = httpResponse?.value(forHTTPHeaderField: "X-Tt-Logid")

        if let httpStatus = httpResponse?.statusCode, !(200...299).contains(httpStatus) {
            if httpStatus == 401 || httpStatus == 403 {
                throw TypolessError.cloudASRAuthenticationFailure
            }
            let body = String(data: responseData, encoding: .utf8) ?? ""
            throw TypolessError.cloudASRNetworkFailure(message: "HTTP \(httpStatus): \(body)")
        }

        switch statusCode {
        case "", "20000000":
            break
        case "20000003", "45000002":
            throw TypolessError.cloudASREmptyResponse
        case "401", "403":
            throw TypolessError.cloudASRAuthenticationFailure
        default:
            throw TypolessError.cloudASRInvalidResponse(detail: "[\(statusCode)] \(statusMessage)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let result = json["result"] as? [String: Any] else {
            throw TypolessError.cloudASRInvalidResponse(detail: "火山引擎 ASR 响应 JSON 无法解析")
        }

        guard let text = (result["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw TypolessError.cloudASREmptyResponse
        }

        return TranscriptResult(text: text, requestId: logID, durationMs: durationMs)
    }
}
