import CommonCrypto
import Foundation
import os.log

/// 腾讯云一句话识别 Provider
///
/// 直接调用腾讯云 Cloud API，不依赖 SDK。
/// 首版仅暴露 SecretId / SecretKey，按中英混合场景调用。
/// 请求超时固定 15 秒。
final class TencentSentenceASRProvider: ASRProvider, @unchecked Sendable {

    private static let timeout: TimeInterval = 15
    private static let service = "asr"
    private static let host = "asr.tencentcloudapi.com"
    private static let action = "SentenceRecognition"
    private static let version = "2019-06-14"
    private static let region = "ap-guangzhou"
    private static let engineModelType = "16k_zh_en"

    private let logger = Logger(subsystem: "com.isecret.typoless", category: "TencentASR")
    private let secretId: String
    private let secretKey: String

    init(secretId: String, secretKey: String) {
        self.secretId = secretId
        self.secretKey = secretKey
    }

    // MARK: - ASRProvider

    func recognize(audioData: Data) async throws -> TranscriptResult {
        guard !secretId.isEmpty, !secretKey.isEmpty else {
            throw TypolessError.cloudASRConfigurationIncomplete
        }

        let base64Audio = audioData.base64EncodedString()
        let dataLen = audioData.count

        let requestBody: [String: Any] = [
            "ProjectId": 0,
            "SubServiceType": 2,
            "EngSerViceType": Self.engineModelType,
            "SourceType": 1,
            "VoiceFormat": "wav",
            "Data": base64Audio,
            "DataLen": dataLen,
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
        let bodyString = String(data: bodyData, encoding: .utf8)!

        let timestamp = Int(Date().timeIntervalSince1970)
        let dateString = Self.utcDateString(timestamp: timestamp)

        // 构建签名
        let authorization = try buildAuthorization(
            bodyString: bodyString,
            timestamp: timestamp,
            dateString: dateString
        )

        var request = URLRequest(url: URL(string: "https://\(Self.host)")!)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.timeoutInterval = Self.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.host, forHTTPHeaderField: "Host")
        request.setValue(Self.action, forHTTPHeaderField: "X-TC-Action")
        request.setValue(Self.version, forHTTPHeaderField: "X-TC-Version")
        request.setValue(Self.region, forHTTPHeaderField: "X-TC-Region")
        request.setValue(String(timestamp), forHTTPHeaderField: "X-TC-Timestamp")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

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

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200:
                break
            case 401, 403:
                throw TypolessError.cloudASRAuthenticationFailure
            default:
                let body = String(data: responseData, encoding: .utf8) ?? ""
                throw TypolessError.cloudASRNetworkFailure(message: "HTTP \(httpResponse.statusCode): \(body)")
            }
        }

        return try parseResponse(responseData, durationMs: durationMs)
    }

    // MARK: - Response Parsing

    private func parseResponse(_ data: Data, durationMs: Int) throws -> TranscriptResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseObj = json["Response"] as? [String: Any] else {
            throw TypolessError.cloudASRInvalidResponse(detail: "无法解析响应 JSON")
        }

        // 检查 API 错误
        if let error = responseObj["Error"] as? [String: Any] {
            let code = error["Code"] as? String ?? "Unknown"
            let message = error["Message"] as? String ?? "Unknown error"

            if code.contains("AuthFailure") || code.contains("SecretId") || code.contains("Signature") {
                throw TypolessError.cloudASRAuthenticationFailure
            }
            throw TypolessError.cloudASRInvalidResponse(detail: "[\(code)] \(message)")
        }

        guard let result = responseObj["Result"] as? String,
              !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TypolessError.cloudASREmptyResponse
        }

        return TranscriptResult(
            text: result.trimmingCharacters(in: .whitespacesAndNewlines),
            requestId: responseObj["RequestId"] as? String ?? "",
            durationMs: durationMs
        )
    }

    // MARK: - TC3-HMAC-SHA256 Signing

    private func buildAuthorization(
        bodyString: String,
        timestamp: Int,
        dateString: String
    ) throws -> String {
        let httpRequestMethod = "POST"
        let canonicalURI = "/"
        let canonicalQueryString = ""
        let canonicalHeaders = "content-type:application/json\nhost:\(Self.host)\n"
        let signedHeaders = "content-type;host"
        let hashedPayload = sha256Hex(bodyString)

        let canonicalRequest = [
            httpRequestMethod,
            canonicalURI,
            canonicalQueryString,
            canonicalHeaders,
            signedHeaders,
            hashedPayload,
        ].joined(separator: "\n")

        let credentialScope = "\(dateString)/\(Self.service)/tc3_request"
        let stringToSign = [
            "TC3-HMAC-SHA256",
            String(timestamp),
            credentialScope,
            sha256Hex(canonicalRequest),
        ].joined(separator: "\n")

        let secretDate = hmacSHA256(key: "TC3\(secretKey)".data(using: .utf8)!, message: dateString)
        let secretService = hmacSHA256(key: secretDate, message: Self.service)
        let secretSigning = hmacSHA256(key: secretService, message: "tc3_request")
        let signature = hmacSHA256(key: secretSigning, message: stringToSign).map { String(format: "%02x", $0) }.joined()

        return "TC3-HMAC-SHA256 Credential=\(secretId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
    }

    private func sha256Hex(_ input: String) -> String {
        let data = input.data(using: .utf8)!
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func hmacSHA256(key: Data, message: String) -> Data {
        let messageData = message.data(using: .utf8)!
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        key.withUnsafeBytes { keyPtr in
            messageData.withUnsafeBytes { msgPtr in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), keyPtr.baseAddress, key.count, msgPtr.baseAddress, messageData.count, &hash)
            }
        }
        return Data(hash)
    }

    private static func utcDateString(timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
