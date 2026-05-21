import CommonCrypto
import Foundation

final class AliyunSentenceASRProvider: ASRProvider, @unchecked Sendable {
    private static let timeout: TimeInterval = 15
    private static let tokenHost = "nls-meta.cn-shanghai.aliyuncs.com"
    private static let tokenVersion = "2019-02-28"
    private static let speechURL = URL(string: "https://nls-gateway-cn-shanghai.aliyuncs.com/stream/v1/asr")!

    private let accessKeyId: String
    private let accessKeySecret: String
    private let appKey: String

    init(accessKeyId: String, accessKeySecret: String, appKey: String) {
        self.accessKeyId = accessKeyId
        self.accessKeySecret = accessKeySecret
        self.appKey = appKey
    }

    func recognize(audioData: Data, timeout: TimeInterval? = nil) async throws -> TranscriptResult {
        guard !accessKeyId.isEmpty, !accessKeySecret.isEmpty, !appKey.isEmpty else {
            throw TypolessError.cloudASRConfigurationIncomplete
        }

        let effectiveTimeout = timeout ?? Self.timeout

        let token = try await fetchToken()
        var components = URLComponents(url: Self.speechURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "appkey", value: appKey),
            URLQueryItem(name: "format", value: "wav"),
            URLQueryItem(name: "sample_rate", value: "16000"),
        ]

        guard let url = components?.url else {
            throw TypolessError.cloudASRInvalidResponse(detail: "阿里云 ASR 请求地址无效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = audioData
        request.timeoutInterval = effectiveTimeout
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-NLS-Token")

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

        return try parseRecognitionResponse(responseData, durationMs: durationMs)
    }

    private func fetchToken() async throws -> String {
        let timestamp = Self.iso8601Timestamp()
        let nonce = UUID().uuidString
        var parameters: [String: String] = [
            "AccessKeyId": accessKeyId,
            "Action": "CreateToken",
            "Format": "JSON",
            "RegionId": "cn-shanghai",
            "SignatureMethod": "HMAC-SHA1",
            "SignatureNonce": nonce,
            "SignatureVersion": "1.0",
            "Timestamp": timestamp,
            "Version": Self.tokenVersion,
        ]

        let signature = sign(parameters: parameters)
        parameters["Signature"] = signature
        let query = canonicalQuery(from: parameters)

        guard let url = URL(string: "https://\(Self.tokenHost)/?\(query)") else {
            throw TypolessError.cloudASRInvalidResponse(detail: "阿里云 Token 请求地址无效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.timeout

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw TypolessError.cloudASRNetworkFailure(message: error.localizedDescription)
        } catch {
            throw TypolessError.cloudASRNetworkFailure(message: error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200:
                break
            case 401, 403:
                throw TypolessError.cloudASRAuthenticationFailure
            default:
                let body = String(data: data, encoding: .utf8) ?? ""
                throw TypolessError.cloudASRNetworkFailure(message: "HTTP \(httpResponse.statusCode): \(body)")
            }
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TypolessError.cloudASRInvalidResponse(detail: "阿里云 Token 响应 JSON 无法解析")
        }

        if let code = json["Code"] as? String, code != "200" {
            if code.lowercased().contains("invalidaccesskey") || code.lowercased().contains("signature") {
                throw TypolessError.cloudASRAuthenticationFailure
            }
            let message = json["Message"] as? String ?? "Unknown error"
            throw TypolessError.cloudASRInvalidResponse(detail: "[\(code)] \(message)")
        }

        if let token = ((json["Token"] as? [String: Any])?["Id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            return token
        }

        throw TypolessError.cloudASRInvalidResponse(detail: "阿里云 Token 响应缺少 Token.Id")
    }

    private func parseRecognitionResponse(_ data: Data, durationMs: Int) throws -> TranscriptResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TypolessError.cloudASRInvalidResponse(detail: "阿里云 ASR 响应 JSON 无法解析")
        }

        if let status = json["status"] as? Int, status != 20000000 {
            let message = json["message"] as? String ?? "Unknown error"
            if status == 40000004 || status == 40000005 {
                throw TypolessError.cloudASRAuthenticationFailure
            }
            throw TypolessError.cloudASRInvalidResponse(detail: "[\(status)] \(message)")
        }

        guard let result = (json["result"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !result.isEmpty else {
            throw TypolessError.cloudASREmptyResponse
        }

        return TranscriptResult(
            text: result,
            requestId: json["request_id"] as? String,
            durationMs: durationMs
        )
    }

    private func sign(parameters: [String: String]) -> String {
        let canonicalizedQuery = canonicalQuery(from: parameters)
        let stringToSign = "GET&%2F&\(percentEncode(canonicalizedQuery))"
        let key = "\(accessKeySecret)&"
        let signatureData = hmacSHA1(key: key, message: stringToSign)
        return signatureData.base64EncodedString()
    }

    private func canonicalQuery(from parameters: [String: String]) -> String {
        parameters
            .sorted { $0.key < $1.key }
            .map { "\(percentEncode($0.key))=\(percentEncode($0.value))" }
            .joined(separator: "&")
    }

    private func hmacSHA1(key: String, message: String) -> Data {
        let keyData = Data(key.utf8)
        let messageData = Data(message.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))

        keyData.withUnsafeBytes { keyBuffer in
            messageData.withUnsafeBytes { messageBuffer in
                CCHmac(
                    CCHmacAlgorithm(kCCHmacAlgSHA1),
                    keyBuffer.baseAddress,
                    keyData.count,
                    messageBuffer.baseAddress,
                    messageData.count,
                    &digest
                )
            }
        }

        return Data(digest)
    }

    private func percentEncode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "+", with: "%20")
            .replacingOccurrences(of: "*", with: "%2A")
            .replacingOccurrences(of: "%7E", with: "~")
            ?? value
    }

    private static func iso8601Timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }
}
