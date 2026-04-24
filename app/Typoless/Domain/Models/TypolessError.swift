import Foundation

/// 统一错误模型，覆盖主链路所有可预期的失败场景
enum TypolessError: Error, Equatable, Sendable {
    case microphonePermissionDenied
    case accessibilityPermissionDenied
    case invalidTencentCredentials(requestId: String?)
    case tencentNetworkFailure(message: String)
    case tencentASRFailure(code: String?, message: String?, requestId: String?)
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
        case .invalidTencentCredentials:
            "腾讯云凭证无效，请检查 SecretId 和 SecretKey"
        case .tencentNetworkFailure:
            "腾讯云网络连接失败，请检查网络"
        case .tencentASRFailure(_, let message, _):
            message ?? "语音识别失败，请重试"
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
