import CommonCrypto
import Foundation

final class XunfeiSentenceASRProvider: ASRProvider, CloudASRValidating, @unchecked Sendable {
    private static let host = "iat-api.xfyun.cn"
    private static let path = "/v2/iat"
    private static let chunkSize = 1280
    private static let frameIntervalMs: UInt64 = 40
    private static let timeoutSeconds: UInt64 = 15

    private let appID: String
    private let apiKey: String
    private let apiSecret: String

    init(appID: String, apiKey: String, apiSecret: String) {
        self.appID = appID
        self.apiKey = apiKey
        self.apiSecret = apiSecret
    }

    func recognize(audioData: Data, timeout: TimeInterval? = nil) async throws -> TranscriptResult {
        guard !appID.isEmpty, !apiKey.isEmpty, !apiSecret.isEmpty else {
            throw TypolessError.cloudASRConfigurationIncomplete
        }

        let effectiveTimeout = timeout.map { UInt64($0) } ?? Self.timeoutSeconds

        return try await withTimeout(seconds: effectiveTimeout) { [self] in
            try await self.performRecognition(audioData: audioData)
        }
    }

    func validateCredentials() async throws {
        let silentAudio = WAVAudioEncoder.encodePCM16(pcmData: Data(repeating: 0, count: 3200), sampleRate: 16_000, channels: 1)
        _ = try await recognize(audioData: silentAudio, timeout: 15)
    }

    private func performRecognition(audioData: Data) async throws -> TranscriptResult {
        let pcmData = try WAVAudioDataExtractor.extractPCMData(from: audioData)
        let requestURL = try buildAuthorizedURL()
        let websocket = URLSession.shared.webSocketTask(with: requestURL)
        websocket.resume()

        let accumulator = XunfeiTranscriptAccumulator()
        let startTime = Date()

        async let receivedText: String = receiveMessages(from: websocket, accumulator: accumulator)
        do {
            try await sendAudioFrames(pcmData, over: websocket)
            let text = try await receivedText
            let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
            let requestID = await accumulator.requestID
            websocket.cancel(with: .normalClosure, reason: nil)
            return TranscriptResult(text: text, requestId: requestID, durationMs: durationMs)
        } catch {
            websocket.cancel(with: .goingAway, reason: nil)
            throw mapWebSocketError(error)
        }
    }

    private func buildAuthorizedURL() throws -> URL {
        let date = Self.rfc1123DateString()
        let signatureOrigin = "host: \(Self.host)\ndate: \(date)\nGET \(Self.path) HTTP/1.1"
        let signature = hmacSHA256Base64(key: apiSecret, message: signatureOrigin)
        let authorizationOrigin = "api_key=\"\(apiKey)\", algorithm=\"hmac-sha256\", headers=\"host date request-line\", signature=\"\(signature)\""
        let authorization = Data(authorizationOrigin.utf8).base64EncodedString()

        var components = URLComponents()
        components.scheme = "wss"
        components.host = Self.host
        components.path = Self.path
        components.queryItems = [
            URLQueryItem(name: "authorization", value: authorization),
            URLQueryItem(name: "date", value: date),
            URLQueryItem(name: "host", value: Self.host),
        ]

        guard let url = components.url else {
            throw TypolessError.cloudASRInvalidResponse(detail: "科大讯飞 WebSocket 地址无效")
        }
        return url
    }

    private func sendAudioFrames(_ pcmData: Data, over websocket: URLSessionWebSocketTask) async throws {
        let chunks = pcmData.chunked(into: Self.chunkSize)
        guard !chunks.isEmpty else {
            throw TypolessError.cloudASREmptyResponse
        }

        for (index, chunk) in chunks.enumerated() {
            let status: Int
            if index == 0 {
                status = chunks.count == 1 ? 2 : 0
            } else if index == chunks.count - 1 {
                status = 2
            } else {
                status = 1
            }

            let payload = try buildFramePayload(chunk: chunk, status: status, isFirstFrame: index == 0)
            try await websocket.send(.string(payload))

            if status != 2 {
                try await Task.sleep(for: .milliseconds(Self.frameIntervalMs))
            }
        }
    }

    private func buildFramePayload(chunk: Data, status: Int, isFirstFrame: Bool) throws -> String {
        var payload: [String: Any] = [
            "data": [
                "status": status,
                "format": "audio/L16;rate=16000",
                "audio": chunk.base64EncodedString(),
                "encoding": "raw",
            ],
        ]

        if isFirstFrame {
            payload["common"] = ["app_id": appID]
            payload["business"] = [
                "language": "zh_cn",
                "domain": "iat",
                "accent": "mandarin",
                "vad_eos": 6000,
            ]
        }

        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw TypolessError.cloudASRInvalidResponse(detail: "科大讯飞请求体编码失败")
        }
        return text
    }

    private func receiveMessages(
        from websocket: URLSessionWebSocketTask,
        accumulator: XunfeiTranscriptAccumulator
    ) async throws -> String {
        while true {
            let websocketMessage = try await websocket.receive()
            let messageData: Data

            switch websocketMessage {
            case .string(let text):
                messageData = Data(text.utf8)
            case .data(let data):
                messageData = data
            @unknown default:
                throw TypolessError.cloudASRInvalidResponse(detail: "科大讯飞返回了未知消息类型")
            }

            guard let json = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any] else {
                throw TypolessError.cloudASRInvalidResponse(detail: "科大讯飞响应 JSON 无法解析")
            }

            let code = json["code"] as? Int ?? -1
            let errorMessage = json["message"] as? String ?? "Unknown error"

            if let sid = json["sid"] as? String {
                await accumulator.setRequestID(sid)
            }

            if code != 0 {
                if errorMessage.lowercased().contains("auth") || errorMessage.lowercased().contains("signature") {
                    throw TypolessError.cloudASRAuthenticationFailure
                }
                throw TypolessError.cloudASRInvalidResponse(detail: "[\(code)] \(errorMessage)")
            }

            guard let data = json["data"] as? [String: Any],
                  let result = data["result"] as? [String: Any] else {
                continue
            }

            let text = XunfeiTranscriptAccumulator.extractText(result: result)
            let sn = result["sn"] as? Int
            let replaceRange: ClosedRange<Int>?
            if let pgs = result["pgs"] as? String,
               pgs == "rpl",
               let ranges = result["rg"] as? [Int],
               ranges.count == 2 {
                replaceRange = ranges[0]...ranges[1]
            } else {
                replaceRange = nil
            }

            await accumulator.absorb(text: text, sn: sn, replaceRange: replaceRange)

            if let status = data["status"] as? Int, status == 2 {
                let finalText = await accumulator.finalText
                if finalText.isEmpty {
                    throw TypolessError.cloudASREmptyResponse
                }
                return finalText
            }
        }
    }

    private func mapWebSocketError(_ error: Error) -> TypolessError {
        if let typolessError = error as? TypolessError {
            return typolessError
        }
        if let urlError = error as? URLError {
            return .cloudASRNetworkFailure(message: urlError.localizedDescription)
        }
        return .cloudASRNetworkFailure(message: error.localizedDescription)
    }

    private func hmacSHA256Base64(key: String, message: String) -> String {
        let keyData = Data(key.utf8)
        let messageData = Data(message.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))

        keyData.withUnsafeBytes { keyBuffer in
            messageData.withUnsafeBytes { messageBuffer in
                CCHmac(
                    CCHmacAlgorithm(kCCHmacAlgSHA256),
                    keyBuffer.baseAddress,
                    keyData.count,
                    messageBuffer.baseAddress,
                    messageData.count,
                    &digest
                )
            }
        }

        return Data(digest).base64EncodedString()
    }

    private func withTimeout<T: Sendable>(seconds: UInt64 = XunfeiSentenceASRProvider.timeoutSeconds, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw TypolessError.cloudASRNetworkFailure(message: "请求超时")
            }

            guard let result = try await group.next() else {
                throw TypolessError.cloudASRNetworkFailure(message: "请求超时")
            }
            group.cancelAll()
            return result
        }
    }

    private static func rfc1123DateString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: Date())
    }
}

private actor XunfeiTranscriptAccumulator {
    private var requestIDValue: String?
    private var segments: [Int: String] = [:]
    private var fallbackOrder: [String] = []

    var requestID: String? {
        requestIDValue
    }

    var finalText: String {
        let ordered = segments.keys.sorted().compactMap { segments[$0] }.joined()
        if !ordered.isEmpty {
            return ordered.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return fallbackOrder.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setRequestID(_ requestID: String) {
        requestIDValue = requestID
    }

    func absorb(text: String, sn: Int?, replaceRange: ClosedRange<Int>?) {
        guard !text.isEmpty else { return }

        if let sn {
            if let replaceRange {
                for index in replaceRange {
                    segments.removeValue(forKey: index)
                }
            }
            segments[sn] = text
        } else {
            fallbackOrder.append(text)
        }
    }

    static func extractText(result: [String: Any]) -> String {
        guard let ws = result["ws"] as? [[String: Any]] else { return "" }
        return ws
            .compactMap { item in
                guard let cw = item["cw"] as? [[String: Any]] else { return nil }
                return cw.compactMap { $0["w"] as? String }.joined()
            }
            .joined()
    }
}

private extension Data {
    func chunked(into size: Int) -> [Data] {
        guard size > 0, !isEmpty else { return [] }

        var chunks: [Data] = []
        var index = startIndex
        while index < endIndex {
            let nextIndex = Swift.min(index + size, endIndex)
            chunks.append(subdata(in: index..<nextIndex))
            index = nextIndex
        }
        return chunks
    }
}
