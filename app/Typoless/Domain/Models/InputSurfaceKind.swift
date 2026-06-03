import Foundation

/// 聚焦输入面的粗粒度分类，用于给 LLM 提供弱上下文参考
enum InputSurfaceKind: String, Codable, Equatable, Sendable {
    case chatComposer
    case documentEditor
    case searchField
    case singleLineForm
    case unknown
}
