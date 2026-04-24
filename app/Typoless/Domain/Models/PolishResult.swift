import Foundation

/// LLM 润色结果模型
struct PolishResult: Sendable {
    let text: String
    let source: Source

    enum Source: String, Sendable {
        case llm
        case fallback
    }
}
