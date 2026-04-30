import Foundation

/// 统一错误模型，覆盖主链路所有可预期的失败场景
enum TypolessError: Error, Equatable, Sendable {
    case microphonePermissionDenied
    case accessibilityPermissionDenied
    // ASR 通用错误
    case asrEmptyAudio
    case asrPlatformNotReady(detail: String)
    // 本地音频预处理错误
    case audioPreprocessFailure(message: String)
    // 本地 ASR 识别错误
    case asrBinaryNotFound
    case asrModelMissing
    case asrRuntimeMissing
    case asrProcessFailure(message: String)
    // 云端 ASR 错误
    case cloudASRConfigurationIncomplete
    case cloudASRAuthenticationFailure
    case cloudASRNetworkFailure(message: String)
    case cloudASREmptyResponse
    case cloudASRInvalidResponse(detail: String)
    // LLM 错误
    case llmConfigurationIncomplete
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
        case .asrPlatformNotReady(let detail):
            "语音识别未就绪：\(detail)"
        case .asrBinaryNotFound:
            "本地识别引擎未就绪，请重新安装应用"
        case .asrModelMissing:
            "本地识别模型缺失，请在设置页下载模型"
        case .asrRuntimeMissing:
            "本地识别引擎缺失，请运行资源准备脚本"
        case .asrProcessFailure(let message):
            "本地语音识别失败：\(message)"
        case .audioPreprocessFailure(let message):
            "音频预处理失败：\(message)"
        case .cloudASRConfigurationIncomplete:
            "云端 ASR 配置未完成，请填写 SecretId 和 SecretKey"
        case .cloudASRAuthenticationFailure:
            "云端 ASR 认证失败，请检查 SecretId 和 SecretKey"
        case .cloudASRNetworkFailure:
            "云端 ASR 请求失败，请检查网络"
        case .cloudASREmptyResponse:
            "云端 ASR 返回空结果"
        case .cloudASRInvalidResponse(let detail):
            "云端 ASR 响应异常：\(detail)"
        case .llmConfigurationIncomplete:
            "LLM 配置未完成，请填写 Base URL、API Key 和 Model"
        case .invalidLLMConfiguration(let detail):
            "LLM 配置异常：\(detail)"
        case .llmNetworkFailure:
            "LLM 请求失败，请检查配置或网络"
        case .llmEmptyResponse:
            "LLM 返回空结果，请检查模型或网关配置"
        case .textInjectionFailure(let detail):
            "文本注入失败：\(detail)"
        case .sessionCancelled:
            "已取消"
        }
    }

    /// 映射为 HUD 短错误分类
    var hudFailureReason: HUDFailureReason {
        switch self {
        case .microphonePermissionDenied, .accessibilityPermissionDenied:
            .permissionDenied
        case .asrBinaryNotFound, .asrModelMissing, .asrRuntimeMissing, .asrPlatformNotReady:
            .resourceMissing
        case .asrEmptyAudio, .cloudASREmptyResponse:
            .notHeard
        case .asrProcessFailure, .audioPreprocessFailure,
             .cloudASRConfigurationIncomplete, .cloudASRAuthenticationFailure,
             .cloudASRNetworkFailure, .cloudASRInvalidResponse:
            .recognitionFailed
        case .llmConfigurationIncomplete, .invalidLLMConfiguration,
             .llmNetworkFailure, .llmEmptyResponse:
            .polishFailed
        case .textInjectionFailure:
            .injectionFailed
        case .sessionCancelled:
            .recognitionFailed
        }
    }
}
