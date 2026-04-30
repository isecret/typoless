import Foundation

/// HUD 失败原因分类，用于展示简明短文案
enum HUDFailureReason: Equatable, Sendable {
    case permissionDenied    // 缺少权限
    case resourceMissing     // 资源缺失
    case notHeard            // 没听清（空音频/空结果）
    case recognitionFailed   // 识别失败
    case polishFailed        // 润色失败
    case injectionFailed     // 写入失败

    /// HUD 短文案
    var shortLabel: String {
        switch self {
        case .permissionDenied: "缺少权限"
        case .resourceMissing: "资源缺失"
        case .notHeard: "没听清"
        case .recognitionFailed: "识别失败"
        case .polishFailed: "润色失败"
        case .injectionFailed: "写入失败"
        }
    }
}

/// HUD 显示状态模型
enum HUDState: Equatable, Sendable {
    case hidden
    case recording
    case processing
    case success
    case failure(HUDFailureReason)
    case cancelled
}
