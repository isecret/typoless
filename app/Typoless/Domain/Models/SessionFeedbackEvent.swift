import Foundation

/// 会话反馈事件，由 SessionCoordinator 发出，驱动 HUD 和音效
enum SessionFeedbackEvent: Sendable {
    case recordingStarted
    /// 录音器已启动且硬件配置已稳定，可安全播放开始音效
    case startSoundCue
    case recordingStopped
    case modeSwitched(TextProcessingMode)
    case processingFinished
    case processingCancelled
    case processingFailed(HUDFailureReason)
}
