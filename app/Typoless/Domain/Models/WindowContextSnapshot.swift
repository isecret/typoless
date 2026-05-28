import Foundation

/// 当前聚焦输入环境的会话级快照，仅在内存中短暂保存
struct WindowContextSnapshot: Equatable, Sendable {
    let appName: String?
    let bundleID: String?
    let windowTitle: String?
    let surfaceKind: InputSurfaceKind
    let elementRole: String?
    let elementSubrole: String?
    let placeholder: String?
    let selectedText: String?
    let surroundingTextBefore: String?
    let surroundingTextAfter: String?
    let nearbyLabels: [String]
}
