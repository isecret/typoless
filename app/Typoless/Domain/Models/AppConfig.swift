import Foundation

// MARK: - LLM 配置（不含密钥）

struct LLMConfig: Codable, Equatable, Sendable {
    var baseURL: String = ""
    var model: String = ""
    var thinkingDisabled: Bool = false
}

// MARK: - ASR 平台配置

/// ASR 平台类型
enum ASRPlatform: String, Codable, Equatable, Sendable, CaseIterable {
    case localSenseVoice = "localSenseVoice"
    case tencentCloudSentence = "tencentCloudSentence"
    case aliyunSentence = "aliyunSentence"
    case volcengineSentence = "volcengineSentence"
    case xunfeiSentence = "xunfeiSentence"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "localFunASR", "localSenseVoice":
            self = .localSenseVoice
        case "tencentCloudSentence":
            self = .tencentCloudSentence
        case "aliyunSentence":
            self = .aliyunSentence
        case "volcengineSentence":
            self = .volcengineSentence
        case "xunfeiSentence":
            self = .xunfeiSentence
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported ASR platform: \(rawValue)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var displayName: String {
        switch self {
        case .localSenseVoice:
            "本地 SenseVoice"
        case .tencentCloudSentence:
            "腾讯云"
        case .aliyunSentence:
            "阿里云"
        case .volcengineSentence:
            "火山引擎"
        case .xunfeiSentence:
            "科大讯飞"
        }
    }

    var cloudConfigSummary: String {
        switch self {
        case .localSenseVoice:
            "本地模式：语音数据仅在本机处理，不会发送到云端 ASR 服务。"
        case .tencentCloudSentence:
            "腾讯云模式：语音会发送到腾讯云一句话识别服务。"
        case .aliyunSentence:
            "阿里云模式：语音会发送到阿里云语音识别服务。"
        case .volcengineSentence:
            "火山引擎模式：语音会发送到火山引擎语音识别服务。"
        case .xunfeiSentence:
            "科大讯飞模式：语音会发送到科大讯飞语音识别服务。"
        }
    }

    var documentationURL: URL {
        switch self {
        case .localSenseVoice:
            URL(string: "https://k2-fsa.github.io/sherpa/onnx/sense-voice/index.html")!
        case .tencentCloudSentence:
            URL(string: "https://cloud.tencent.com/document/product/1093/35646")!
        case .aliyunSentence:
            URL(string: "https://help.aliyun.com/zh/isi/developer-reference/short-sentence-recognition")!
        case .volcengineSentence:
            URL(string: "https://www.volcengine.com/docs/6561/1257584")!
        case .xunfeiSentence:
            URL(string: "https://www.xfyun.cn/doc/asr/voicedictation/API.html")!
        }
    }
}

/// ASR 总配置
struct ASRConfig: Codable, Equatable, Sendable {
    var selectedPlatform: ASRPlatform = .localSenseVoice
    var local: LocalASRConfig = LocalASRConfig()
    var tencentCloud: TencentASRConfig = TencentASRConfig()
    var aliyun: AliyunASRConfig = AliyunASRConfig()
    var volcengine: VolcengineASRConfig = VolcengineASRConfig()
    var xunfei: XunfeiASRConfig = XunfeiASRConfig()

    enum CodingKeys: String, CodingKey {
        case selectedPlatform
        case local
        case tencentCloud
        case aliyun
        case volcengine
        case xunfei
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedPlatform = try container.decodeIfPresent(ASRPlatform.self, forKey: .selectedPlatform) ?? .localSenseVoice
        local = try container.decodeIfPresent(LocalASRConfig.self, forKey: .local) ?? LocalASRConfig()
        tencentCloud = try container.decodeIfPresent(TencentASRConfig.self, forKey: .tencentCloud) ?? TencentASRConfig()
        aliyun = try container.decodeIfPresent(AliyunASRConfig.self, forKey: .aliyun) ?? AliyunASRConfig()
        volcengine = try container.decodeIfPresent(VolcengineASRConfig.self, forKey: .volcengine) ?? VolcengineASRConfig()
        xunfei = try container.decodeIfPresent(XunfeiASRConfig.self, forKey: .xunfei) ?? XunfeiASRConfig()
    }

    func isReady(localModelsAvailable: Bool) -> Bool {
        switch selectedPlatform {
        case .localSenseVoice:
            return localModelsAvailable
        case .tencentCloudSentence:
            return tencentCloud.isReady
        case .aliyunSentence:
            return aliyun.isReady
        case .volcengineSentence:
            return volcengine.isReady
        case .xunfeiSentence:
            return xunfei.isReady
        }
    }

    func notReadyReason(localModelsAvailable: Bool) -> String? {
        guard !isReady(localModelsAvailable: localModelsAvailable) else { return nil }

        switch selectedPlatform {
        case .localSenseVoice:
            return "本地模型未下载，请在设置页下载"
        case .tencentCloudSentence:
            return tencentCloud.notReadyReason(platformName: "腾讯云")
        case .aliyunSentence:
            return aliyun.notReadyReason(platformName: "阿里云")
        case .volcengineSentence:
            return volcengine.notReadyReason(platformName: "火山引擎")
        case .xunfeiSentence:
            return xunfei.notReadyReason(platformName: "科大讯飞")
        }
    }
}

/// 本地 ASR 模型状态
enum LocalModelStatus: String, Codable, Equatable, Sendable {
    case notDownloaded = "notDownloaded"
    case downloading = "downloading"
    case ready = "ready"
    case failed = "failed"
}

enum CloudASRValidationStatus: String, Codable, Equatable, Sendable {
    case unvalidated = "unvalidated"
    case validating = "validating"
    case verified = "verified"
    case failed = "failed"
}

protocol CloudASRConfigState: Sendable {
    var isComplete: Bool { get }
    var validationStatus: CloudASRValidationStatus { get set }
    var lastValidationError: String? { get set }
}

extension CloudASRConfigState {
    var isReady: Bool {
        isComplete && validationStatus == .verified
    }

    func notReadyReason(platformName: String) -> String {
        if !isComplete {
            return incompleteReason(platformName: platformName)
        }

        switch validationStatus {
        case .verified:
            return "\(platformName) ASR 未知未就绪状态"
        case .validating:
            return "\(platformName) ASR 正在验证，请稍候"
        case .unvalidated:
            return "\(platformName) ASR 尚未通过真实请求验证，请先在设置页完成验证"
        case .failed:
            if let lastValidationError,
               !lastValidationError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "\(platformName) ASR 验证失败：\(lastValidationError)"
            }
            return "\(platformName) ASR 验证失败，请检查配置并重试"
        }
    }

    func incompleteReason(platformName: String) -> String {
        "\(platformName) ASR 配置不完整，请补全必填字段"
    }
}

/// 本地 ASR 配置
struct LocalASRConfig: Codable, Equatable, Sendable {
    var modelStatus: LocalModelStatus = .notDownloaded
    var lastError: String?
    var mirrorSource: String?

    /// 模型固定版本标识
    static let modelVersion = "sensevoice-small-onnx-int8-2024-07-17"

    static let modelFileName = "model.int8.onnx"
    static let tokensFileName = "tokens.txt"

    /// 模型根目录
    static var modelRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".typoless/models/sensevoice-small-onnx", isDirectory: true)
    }

    static var requiredFileNames: [String] {
        [modelFileName, tokensFileName]
    }
}

/// 腾讯云一句话识别配置
struct TencentASRConfig: Codable, Equatable, Sendable {
    var secretId: String = ""
    var secretKey: String = ""
    var validationStatus: CloudASRValidationStatus = .unvalidated
    var lastValidationError: String?

    var isComplete: Bool {
        !secretId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !secretKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 阿里云一句话识别配置
struct AliyunASRConfig: Codable, Equatable, Sendable {
    var accessKeyId: String = ""
    var accessKeySecret: String = ""
    var appKey: String = ""
    var validationStatus: CloudASRValidationStatus = .unvalidated
    var lastValidationError: String?

    var isComplete: Bool {
        !accessKeyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !accessKeySecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !appKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 火山引擎文件识别配置
struct VolcengineASRConfig: Codable, Equatable, Sendable {
    var apiKey: String = ""
    var validationStatus: CloudASRValidationStatus = .unvalidated
    var lastValidationError: String?

    var isComplete: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 科大讯飞语音听写配置
struct XunfeiASRConfig: Codable, Equatable, Sendable {
    var appID: String = ""
    var apiKey: String = ""
    var apiSecret: String = ""
    var validationStatus: CloudASRValidationStatus = .unvalidated
    var lastValidationError: String?

    var isComplete: Bool {
        !appID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension TencentASRConfig: CloudASRConfigState {
    func incompleteReason(platformName: String) -> String {
        "\(platformName) ASR 配置不完整，请填写 SecretId 和 SecretKey"
    }
}

extension AliyunASRConfig: CloudASRConfigState {
    func incompleteReason(platformName: String) -> String {
        "\(platformName) ASR 配置不完整，请填写 AccessKey ID、AccessKey Secret 和 AppKey"
    }
}

extension VolcengineASRConfig: CloudASRConfigState {
    func incompleteReason(platformName: String) -> String {
        "\(platformName) ASR 配置不完整，请填写 API Key"
    }
}

extension XunfeiASRConfig: CloudASRConfigState {
    func incompleteReason(platformName: String) -> String {
        "\(platformName) ASR 配置不完整，请填写 AppID、API Key 和 API Secret"
    }
}

// MARK: - 通用配置

struct AudioInputConfig: Codable, Equatable, Sendable {
    var selectedDeviceID: String?
    var selectedDeviceName: String?

    static let systemDefault = AudioInputConfig(
        selectedDeviceID: nil,
        selectedDeviceName: nil
    )

    var usesSystemDefault: Bool {
        selectedDeviceID == nil
    }
}

struct AudioInputDevice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

struct GeneralConfig: Codable, Equatable, Sendable {
    var hotkey: HotkeyCombo = .default
    var interactionSoundEnabled: Bool = true
    var translationTargetLanguage: TranslationTargetLanguage = .english
    var launchAtLogin: Bool = false

    init(
        hotkey: HotkeyCombo = .default,
        interactionSoundEnabled: Bool = true,
        translationTargetLanguage: TranslationTargetLanguage = .english,
        launchAtLogin: Bool = false
    ) {
        self.hotkey = hotkey
        self.interactionSoundEnabled = interactionSoundEnabled
        self.translationTargetLanguage = translationTargetLanguage
        self.launchAtLogin = launchAtLogin
    }
}

// MARK: - 快捷键组合

struct HotkeyCombo: Codable, Equatable, Sendable {
    var keyCode: UInt16
    var modifiers: UInt
    var displayString: String

    static let `default` = HotkeyCombo(
        keyCode: 49,    // Space
        modifiers: 0x80120, // Option
        displayString: "⌥ Space"
    )
}
