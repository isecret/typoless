import Foundation

/// 从 LLM 响应中提取并解析结构化 JSON 结果
enum StructuredPolishParser {

    /// 解析结果
    enum ParseResult: Sendable {
        /// 成功解析出合法且语义有效的结构化结果
        case structured(response: LLMStructuredResponse)
        /// JSON 合法但语义不满足 mode 要求，带 fallback text
        case invalidStructure(fallbackText: String)
        /// 非 JSON 或 JSON 解析失败，原始文本作为 fallback
        case plainText(String)
    }

    /// 尝试解析 LLM 返回的内容
    static func parse(content: String) -> ParseResult {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // 尝试提取 JSON（支持直接 JSON 和 code fence 包裹）
        guard let jsonString = extractJSON(from: trimmed),
              let data = jsonString.data(using: .utf8)
        else {
            return .plainText(trimmed)
        }

        // 尝试解码
        let response: LLMStructuredResponse
        do {
            response = try JSONDecoder().decode(LLMStructuredResponse.self, from: data)
        } catch {
            // JSON 解析失败：尝试提取 text 字段作为 fallback
            if let fallback = extractTextField(from: data) {
                return .plainText(fallback)
            }
            return .plainText(trimmed)
        }

        // 语义校验
        let structured = response.toStructuredResult()
        guard structured.isValid else {
            // 结构不满足 mode 要求，退回 text
            let fallback = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fallback.isEmpty else {
                return .plainText(trimmed)
            }
            return .invalidStructure(fallbackText: fallback)
        }

        return .structured(response: response)
    }

    // MARK: - Private

    /// 提取 JSON 字符串：优先直接匹配 `{...}`，其次从 code fence 中提取
    private static func extractJSON(from content: String) -> String? {
        // 直接以 { 开头的 JSON
        if content.hasPrefix("{") {
            return content
        }

        // 从 ```json ... ``` 或 ``` ... ``` 中提取
        let fencePattern = #"```(?:json)?\s*\n?([\s\S]*?)\n?```"#
        if let regex = try? NSRegularExpression(pattern: fencePattern),
           let match = regex.firstMatch(
               in: content,
               range: NSRange(content.startIndex..., in: content)
           ),
           let range = Range(match.range(at: 1), in: content) {
            let extracted = String(content[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if extracted.hasPrefix("{") {
                return extracted
            }
        }

        // 尝试在文本中定位第一个 JSON 对象
        if let startIdx = content.firstIndex(of: "{"),
           let endIdx = content.lastIndex(of: "}") {
            let candidate = String(content[startIdx...endIdx])
            return candidate
        }

        return nil
    }

    /// 从 JSON data 中尝试提取 text 字段（宽容解码）
    private static func extractTextField(from data: Data) -> String? {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = dict["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - LLM Structured Response (wire format)

/// LLM 返回的 JSON 结构（对应 Prompt 定义的 schema）
struct LLMStructuredResponse: Decodable, Equatable, Sendable {
    let mode: PolishMode
    let text: String
    let items: [String]?
    let salutation: String?
    let body: [String]?
    let closing: String?
    let correctionApplied: Bool

    enum CodingKeys: String, CodingKey {
        case mode, text, items, salutation, body, closing
        case correctionApplied = "correction_applied"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(PolishMode.self, forKey: .mode)
        text = try container.decode(String.self, forKey: .text)
        items = try container.decodeIfPresent([String].self, forKey: .items)
        salutation = try container.decodeIfPresent(String.self, forKey: .salutation)
        body = try container.decodeIfPresent([String].self, forKey: .body)
        closing = try container.decodeIfPresent(String.self, forKey: .closing)
        correctionApplied = try container.decodeIfPresent(Bool.self, forKey: .correctionApplied) ?? false
    }

    /// 转为内部结构化结果模型
    func toStructuredResult() -> StructuredPolishResult {
        StructuredPolishResult(
            mode: mode,
            items: items,
            salutation: salutation,
            body: body,
            closing: closing,
            correctionApplied: correctionApplied
        )
    }
}
