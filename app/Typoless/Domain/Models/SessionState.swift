import Foundation

/// 主链路会话状态，驱动菜单栏图标与菜单内容
enum SessionState: String, Equatable, Sendable {
    case idle
    case recording
    case transcribing
    case polishing
    case injecting
    case done
    case error
    case cancelled

    /// 菜单栏 SF Symbol 图标名
    var iconName: String {
        switch self {
        case .idle: "mic"
        case .recording: "mic.fill"
        case .transcribing: "text.bubble"
        case .polishing: "sparkles"
        case .injecting: "text.cursor"
        case .done: "checkmark.circle"
        case .error: "exclamationmark.triangle"
        case .cancelled: "xmark.circle"
        }
    }

    /// 用户可见的状态文本
    var displayText: String {
        switch self {
        case .idle: "空闲"
        case .recording: "录音中"
        case .transcribing: "识别中"
        case .polishing: "润色中"
        case .injecting: "注入中"
        case .done: "完成"
        case .error: "失败"
        case .cancelled: "已取消"
        }
    }

    /// 是否允许用户取消（仅 transcribing / polishing）
    var isCancellable: Bool {
        switch self {
        case .transcribing, .polishing: true
        default: false
        }
    }

    /// 是否处于活跃处理中
    var isProcessing: Bool {
        switch self {
        case .recording, .transcribing, .polishing, .injecting: true
        default: false
        }
    }
}
