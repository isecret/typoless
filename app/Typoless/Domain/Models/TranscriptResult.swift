import Foundation

/// ASR 转写结果统一模型
struct TranscriptResult: Sendable {
    let text: String
    let requestId: String?
    let durationMs: Int
}
