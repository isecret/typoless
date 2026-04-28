import Foundation

/// HUD 显示状态模型
enum HUDState: Equatable, Sendable {
    case hidden
    case recording
    case processing
    case success
    case failure
    case cancelled
}
