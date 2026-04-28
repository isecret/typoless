import Foundation

/// 统一错误模型，覆盖主链路所有可预期的失败场景
enum TypolessError: Error, Equatable, Sendable {
    case microphonePermissionDenied
    case accessibilityPermissionDenied
    // ASR 通用错误
    case asrEmptyAudio
    // 本地 ASR 识别错误
    case asrBinaryNotFound
    case asrModelMissing
    case asrProcessFailure(message: String)
    // LLM 错误
    case invalidLLMConfiguration(detail: String)
    case llmNetworkFailure(message: String)
    case llmEmptyResponse
    case textInjectionFailure(detail: String)
    case sessionCancelled

    /// 用户可理解的错误摘要，用于菜单栏和设置页展示
    var userMessage: String {
        switch self {
        case .microphonePermissionDenied:
            "麦克风权限未开启，无法录音"
        case .accessibilityPermissionDenied:
            "辅助功能权限未开启，无法注入文本"
        case .asrEmptyAudio:
            "录音数据为空，请重试"
        case .asrBinaryNotFound:
            "本地识别引擎未就绪，请重新安装应用"
        case .asrModelMissing:
            "本地识别模型缺失"
        case .asrProcessFailure(let message):
            "本地语音识别失败：\(message)"
        case .invalidLLMConfiguration(let detail):
            "LLM 配置无效：\(detail)"
        case .llmNetworkFailure:
            "LLM 网络连接失败，请检查网络"
        case .llmEmptyResponse:
            "LLM 返回空结果，已使用原始识别文本"
        case .textInjectionFailure(let detail):
            "文本注入失败：\(detail)"
        case .sessionCancelled:
            "已取消"
        }
    }
}
