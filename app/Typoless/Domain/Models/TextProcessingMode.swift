import Foundation

/// 会话处理模式：polish（润色）或 translate（翻译）
enum TextProcessingMode: String, Codable, Equatable, Sendable {
    case polish
    case translate
}
