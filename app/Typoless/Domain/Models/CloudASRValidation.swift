import Foundation

enum CloudASRValidationDisplayStatus: Equatable, Sendable {
    case incomplete
    case checking
    case ready
    case failed
}

struct CloudASRValidationInput: Equatable, Sendable {
    var platform: ASRPlatform
    var asrConfig: ASRConfig

    var isCloudPlatform: Bool {
        platform != .localSenseVoice
    }

    var isComplete: Bool {
        switch platform {
        case .localSenseVoice:
            return false
        case .tencentCloudSentence:
            return asrConfig.tencentCloud.isComplete
        case .aliyunSentence:
            return asrConfig.aliyun.isComplete
        case .volcengineSentence:
            return asrConfig.volcengine.isComplete
        case .xunfeiSentence:
            return asrConfig.xunfei.isComplete
        case .xiaomiMiMoASR:
            return asrConfig.xiaomiMiMo.isComplete
        }
    }

    var fingerprint: String {
        switch platform {
        case .localSenseVoice:
            return platform.rawValue
        case .tencentCloudSentence:
            return "\(platform.rawValue)\n\(asrConfig.tencentCloud.secretId)\n\(asrConfig.tencentCloud.secretKey)"
        case .aliyunSentence:
            return "\(platform.rawValue)\n\(asrConfig.aliyun.accessKeyId)\n\(asrConfig.aliyun.accessKeySecret)\n\(asrConfig.aliyun.appKey)"
        case .volcengineSentence:
            return "\(platform.rawValue)\n\(asrConfig.volcengine.apiKey)"
        case .xunfeiSentence:
            return "\(platform.rawValue)\n\(asrConfig.xunfei.appID)\n\(asrConfig.xunfei.apiKey)\n\(asrConfig.xunfei.apiSecret)"
        case .xiaomiMiMoASR:
            return "\(platform.rawValue)\n\(asrConfig.xiaomiMiMo.apiKey)"
        }
    }
}
