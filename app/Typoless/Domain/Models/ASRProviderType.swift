import Foundation

/// ASR Provider 类型枚举，支持本地 FunASR 和腾讯云两种识别方式
enum ASRProviderType: String, Codable, CaseIterable, Sendable {
    case funasrLocal = "funasrLocal"
    case tencentCloud = "tencentCloud"

    var displayName: String {
        switch self {
        case .funasrLocal: "本地识别 (FunASR)"
        case .tencentCloud: "腾讯云 ASR"
        }
    }

    var description: String {
        switch self {
        case .funasrLocal: "使用内置本地识别，无需额外配置"
        case .tencentCloud: "使用腾讯云语音识别服务，需要配置凭证"
        }
    }
}
