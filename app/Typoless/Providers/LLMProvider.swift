import Foundation

/// OpenAI Chat Completions 兼容 LLM Provider，用于文本润色
struct LLMProvider: Sendable {

    private static let timeout: TimeInterval = 15

    /// 固定系统 Prompt：纠错、去赘词、轻度书面化、补中文标点
    private static let systemPrompt = """
        你是一个中文文本校对助手。请对以下语音识别文本进行修正：
        1. 纠正明显的错别字和语音识别错误
        2. 去除口语赘词（如"嗯"、"啊"、"那个"、"就是"等）
        3. 轻度书面化，使文本更通顺
        4. 补充自然的中文标点符号

        要求：
        - 不要扩写或添加原文未提及的内容
        - 不要改变原意
        - 不要引入原文未提及的事实
        - 只输出修正后的文本，不要附加任何解释或说明
        """

    let baseURL: String
    let apiKey: String
    let model: String

    // MARK: - Public API

    func polish(text: String) async throws -> PolishResult {
        let url = try buildURL()
        let bodyData = try buildRequestBody(text: text)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = Self.timeout

        let data: Data
        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)
            data = responseData

            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200: break
                case 401, 403:
                    throw TypolessError.invalidLLMConfiguration(detail: "认证失败，请检查 API Key")
                case 404:
                    throw TypolessError.invalidLLMConfiguration(detail: "模型不存在或 URL 错误")
                default:
                    let body = String(data: data, encoding: .utf8) ?? ""
                    throw TypolessError.llmNetworkFailure(message: "HTTP \(httpResponse.statusCode): \(body)")
                }
            }
        } catch let error as TypolessError {
            throw error
        } catch let error as URLError {
            throw TypolessError.llmNetworkFailure(message: error.localizedDescription)
        } catch {
            throw TypolessError.llmNetworkFailure(message: error.localizedDescription)
        }

        return try parseResponse(data)
    }

    // MARK: - Request

    private func buildURL() throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmed)/chat/completions") else {
            throw TypolessError.invalidLLMConfiguration(detail: "Base URL 格式无效")
        }
        return url
    }

    private func buildRequestBody(text: String) throws -> Data {
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": text],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Response

    private func parseResponse(_ data: Data) throws -> PolishResult {
        let response: LLMResponse
        do {
            response = try JSONDecoder().decode(LLMResponse.self, from: data)
        } catch {
            throw TypolessError.llmEmptyResponse
        }

        // Check for API error
        if let apiError = response.error {
            if apiError.type == "invalid_request_error" {
                throw TypolessError.invalidLLMConfiguration(detail: apiError.message)
            }
            throw TypolessError.llmNetworkFailure(message: apiError.message)
        }

        guard let content = response.choices?.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw TypolessError.llmEmptyResponse
        }

        return PolishResult(
            text: content.trimmingCharacters(in: .whitespacesAndNewlines),
            source: .llm
        )
    }
}

// MARK: - Response Models

private struct LLMResponse: Decodable {
    let choices: [LLMChoice]?
    let error: LLMError?
}

private struct LLMChoice: Decodable {
    let message: LLMMessage
}

private struct LLMMessage: Decodable {
    let content: String
}

private struct LLMError: Decodable {
    let message: String
    let type: String?
    let code: String?
}
