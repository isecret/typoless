import Foundation

/// 最近记录模型，保存最终文本、时间和状态
struct RecentRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let text: String
    let timestamp: Date
    let status: RecordStatus

    /// 记录状态，对齐 TDD 13.1
    enum RecordStatus: String, Codable, Sendable {
        case success
        case fallbackSuccess
        case failed

        var displayText: String {
            switch self {
            case .success: "成功"
            case .fallbackSuccess: "已回退"
            case .failed: "注入失败"
            }
        }

        var iconName: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .fallbackSuccess: "arrow.uturn.backward.circle.fill"
            case .failed: "exclamationmark.triangle.fill"
            }
        }
    }
}
