import Foundation

/// 会话反馈事件，由 SessionCoordinator 发出，驱动 HUD 和音效
enum SessionFeedbackEvent: Sendable {
    case recordingStarted
    case recordingStopped
    case processingFinished
    case processingCancelled
    case processingFailed
}
