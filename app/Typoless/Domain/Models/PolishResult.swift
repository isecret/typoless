import Foundation

// MARK: - Polish Mode

/// 结构化处理模式：LLM 自动判断输入属于哪种输出形态
enum PolishMode: String, Decodable, Equatable, Sendable {
    case plainText = "plain_text"
    case list
    case message
}

// MARK: - Structured Polish Result

/// 结构化润色结果，由 LLM JSON 响应解析得到
struct StructuredPolishResult: Decodable, Equatable, Sendable {
    let mode: PolishMode
    /// list 模式的条目
    let items: [String]?
    /// message 模式的称呼
    let salutation: String?
    /// message 模式的正文段落
    let body: [String]?
    /// message 模式的结尾
    let closing: String?
    /// 是否触发了显式自我修正
    let correctionApplied: Bool

    enum CodingKeys: String, CodingKey {
        case mode
        case items
        case salutation
        case body
        case closing
        case correctionApplied = "correction_applied"
    }

    /// 语义校验：检查当前 mode 下必要字段是否满足
    var isValid: Bool {
        switch mode {
        case .plainText:
            return true
        case .list:
            guard let items, !items.isEmpty else { return false }
            return true
        case .message:
            guard let body, !body.isEmpty else { return false }
            return true
        }
    }
}

// MARK: - Polish Result

/// LLM 润色结果模型
struct PolishResult: Equatable, Sendable {
    let text: String
    let source: Source
    /// 结构化结果（可选），缺失时调用方退回 text
    let structured: StructuredPolishResult?

    enum Source: String, Sendable {
        case llm
    }

    init(text: String, source: Source, structured: StructuredPolishResult? = nil) {
        self.text = text
        self.source = source
        self.structured = structured
    }
}
