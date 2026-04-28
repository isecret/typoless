import CommonCrypto
import Foundation

/// 腾讯云 ASR 一句话识别 Provider，自实现 HTTP + TC3-HMAC-SHA256 签名
struct TencentASRProvider: ASRProvider, Sendable {

    private static let host = "asr.tencentcloudapi.com"
    private static let service = "asr"
    private static let action = "SentenceRecognition"
    private static let version = "2019-06-14"
    private static let timeout: TimeInterval = 30

    let secretId: String
    let secretKey: String
    let region: String

    // MARK: - Public API

    func recognize(audioData: Data) async throws -> TranscriptResult {
        let timestamp = Int(Date().timeIntervalSince1970)
        let dateString = Self.utcDateString(from: timestamp)

        let bodyData = try buildRequestBody(audioData: audioData)
        let authorization = sign(bodyData: bodyData, timestamp: timestamp, dateString: dateString)

        var request = URLRequest(url: URL(string: "https://\(Self.host)")!)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.host, forHTTPHeaderField: "Host")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue(Self.action, forHTTPHeaderField: "X-TC-Action")
        request.setValue(String(timestamp), forHTTPHeaderField: "X-TC-Timestamp")
        request.setValue(Self.version, forHTTPHeaderField: "X-TC-Version")
        request.setValue(region, forHTTPHeaderField: "X-TC-Region")
        request.timeoutInterval = Self.timeout

        let data: Data
        do {
            let (responseData, _) = try await URLSession.shared.data(for: request)
            data = responseData
        } catch let error as URLError {
            throw TypolessError.tencentNetworkFailure(message: error.localizedDescription)
        }

        return try parseResponse(data)
    }

    // MARK: - Request Body

    private func buildRequestBody(audioData: Data) throws -> Data {
        let body: [String: Any] = [
            "ProjectId": 0,
            "SubServiceType": 2,
            "EngSerViceType": "16k_zh",
            "SourceType": 1,
            "VoiceFormat": "wav",
            "Data": audioData.base64EncodedString(),
            "DataLen": audioData.count,
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Response Parsing

    private func parseResponse(_ data: Data) throws -> TranscriptResult {
        let wrapper: TencentResponse
        do {
            wrapper = try JSONDecoder().decode(TencentResponse.self, from: data)
        } catch {
            throw TypolessError.tencentASRFailure(
                code: nil,
                message: "无法解析识别响应",
                requestId: nil
            )
        }

        let body = wrapper.Response

        if let apiError = body.Error {
            if apiError.Code.hasPrefix("AuthFailure") {
                throw TypolessError.invalidTencentCredentials(requestId: body.RequestId)
            }
            throw TypolessError.tencentASRFailure(
                code: apiError.Code,
                message: apiError.Message,
                requestId: body.RequestId
            )
        }

        guard let text = body.Result, !text.isEmpty else {
            throw TypolessError.tencentASRFailure(
                code: "EmptyTranscript",
                message: "语音识别结果为空",
                requestId: body.RequestId
            )
        }

        return TranscriptResult(
            text: text,
            requestId: body.RequestId,
            durationMs: body.AudioDuration ?? 0
        )
    }

    // MARK: - TC3-HMAC-SHA256 Signing

    private func sign(bodyData: Data, timestamp: Int, dateString: String) -> String {
        let contentType = "application/json; charset=utf-8"
        let hashedPayload = Self.hexString(Self.sha256(bodyData))

        // Step 1: Canonical Request
        let canonicalHeaders = "content-type:\(contentType)\nhost:\(Self.host)\n"
        let signedHeaders = "content-type;host"

        let canonicalRequest = [
            "POST",
            "/",
            "",
            canonicalHeaders,
            signedHeaders,
            hashedPayload,
        ].joined(separator: "\n")

        // Step 2: String to Sign
        let credentialScope = "\(dateString)/\(Self.service)/tc3_request"
        let hashedCanonicalRequest = Self.hexString(Self.sha256(Data(canonicalRequest.utf8)))

        let stringToSign = [
            "TC3-HMAC-SHA256",
            "\(timestamp)",
            credentialScope,
            hashedCanonicalRequest,
        ].joined(separator: "\n")

        // Step 3: Signature
        let secretDate = Self.hmacSHA256(
            key: Data("TC3\(secretKey)".utf8),
            data: Data(dateString.utf8)
        )
        let secretService = Self.hmacSHA256(key: secretDate, data: Data(Self.service.utf8))
        let secretSigning = Self.hmacSHA256(key: secretService, data: Data("tc3_request".utf8))
        let signature = Self.hexString(
            Self.hmacSHA256(key: secretSigning, data: Data(stringToSign.utf8))
        )

        // Step 4: Authorization Header
        return "TC3-HMAC-SHA256 Credential=\(secretId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
    }

    // MARK: - Crypto Helpers

    private static func sha256(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }

    private static func hmacSHA256(key: Data, data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        key.withUnsafeBytes { keyPtr in
            data.withUnsafeBytes { dataPtr in
                CCHmac(
                    CCHmacAlgorithm(kCCHmacAlgSHA256),
                    keyPtr.baseAddress, key.count,
                    dataPtr.baseAddress, data.count,
                    &hash
                )
            }
        }
        return Data(hash)
    }

    private static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func utcDateString(from timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}

// MARK: - Response Models

private struct TencentResponse: Decodable {
    let Response: TencentResponseBody
}

private struct TencentResponseBody: Decodable {
    let Result: String?
    let AudioDuration: Int?
    let WordSize: Int?
    let RequestId: String
    let Error: TencentResponseError?
}

private struct TencentResponseError: Decodable {
    let Code: String
    let Message: String
}
