import AppKit
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
    case xiaomiMiMoASR = "xiaomiMiMoASR"
    case xiaomiMiMoTokenPlanASR = "xiaomiMiMoTokenPlanASR"

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
        case "xiaomiMiMoASR":
            self = .xiaomiMiMoASR
        case "xiaomiMiMoTokenPlanASR":
            self = .xiaomiMiMoTokenPlanASR
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
        case .xiaomiMiMoASR:
            "小米 MiMo"
        case .xiaomiMiMoTokenPlanASR:
            "小米 MiMo（Token Plan）"
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
        case .xiaomiMiMoASR:
            "小米 MiMo 模式：语音会发送到 Xiaomi MiMo ASR 服务。"
        case .xiaomiMiMoTokenPlanASR:
            "小米 MiMo Token Plan 模式：语音会发送到 Xiaomi MiMo Token Plan ASR 服务。"
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
        case .xiaomiMiMoASR:
            URL(string: "https://platform.xiaomimimo.com/docs/zh-CN/api/audio/Speech-Recognition")!
        case .xiaomiMiMoTokenPlanASR:
            URL(string: "https://platform.xiaomimimo.com/docs/zh-CN/api/audio/Speech-Recognition")!
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
    var xiaomiMiMo: XiaomiMiMoASRConfig = XiaomiMiMoASRConfig()
    var xiaomiMiMoTokenPlan: XiaomiMiMoASRConfig = XiaomiMiMoASRConfig()

    enum CodingKeys: String, CodingKey {
        case selectedPlatform
        case local
        case tencentCloud
        case aliyun
        case volcengine
        case xunfei
        case xiaomiMiMo
        case xiaomiMiMoTokenPlan
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
        xiaomiMiMo = try container.decodeIfPresent(XiaomiMiMoASRConfig.self, forKey: .xiaomiMiMo) ?? XiaomiMiMoASRConfig()
        xiaomiMiMoTokenPlan = try container.decodeIfPresent(XiaomiMiMoASRConfig.self, forKey: .xiaomiMiMoTokenPlan) ?? XiaomiMiMoASRConfig()
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
        case .xiaomiMiMoASR:
            return xiaomiMiMo.isReady
        case .xiaomiMiMoTokenPlanASR:
            return xiaomiMiMoTokenPlan.isReady
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
        case .xiaomiMiMoASR:
            return xiaomiMiMo.notReadyReason(platformName: "小米 MiMo")
        case .xiaomiMiMoTokenPlanASR:
            return xiaomiMiMoTokenPlan.notReadyReason(platformName: "小米 MiMo（Token Plan）")
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
    func incompleteReason(platformName: String) -> String
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

    enum CodingKeys: String, CodingKey {
        case secretId
        case secretKey
        case validationStatus
        case lastValidationError
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        secretId = try container.decodeIfPresent(String.self, forKey: .secretId) ?? ""
        secretKey = try container.decodeIfPresent(String.self, forKey: .secretKey) ?? ""
        validationStatus = try container.decodeIfPresent(CloudASRValidationStatus.self, forKey: .validationStatus) ?? .unvalidated
        lastValidationError = try container.decodeIfPresent(String.self, forKey: .lastValidationError)
    }

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

    enum CodingKeys: String, CodingKey {
        case accessKeyId
        case accessKeySecret
        case appKey
        case validationStatus
        case lastValidationError
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessKeyId = try container.decodeIfPresent(String.self, forKey: .accessKeyId) ?? ""
        accessKeySecret = try container.decodeIfPresent(String.self, forKey: .accessKeySecret) ?? ""
        appKey = try container.decodeIfPresent(String.self, forKey: .appKey) ?? ""
        validationStatus = try container.decodeIfPresent(CloudASRValidationStatus.self, forKey: .validationStatus) ?? .unvalidated
        lastValidationError = try container.decodeIfPresent(String.self, forKey: .lastValidationError)
    }

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

    enum CodingKeys: String, CodingKey {
        case apiKey
        case validationStatus
        case lastValidationError
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        validationStatus = try container.decodeIfPresent(CloudASRValidationStatus.self, forKey: .validationStatus) ?? .unvalidated
        lastValidationError = try container.decodeIfPresent(String.self, forKey: .lastValidationError)
    }

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

    enum CodingKeys: String, CodingKey {
        case appID
        case apiKey
        case apiSecret
        case validationStatus
        case lastValidationError
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appID = try container.decodeIfPresent(String.self, forKey: .appID) ?? ""
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        apiSecret = try container.decodeIfPresent(String.self, forKey: .apiSecret) ?? ""
        validationStatus = try container.decodeIfPresent(CloudASRValidationStatus.self, forKey: .validationStatus) ?? .unvalidated
        lastValidationError = try container.decodeIfPresent(String.self, forKey: .lastValidationError)
    }

    var isComplete: Bool {
        !appID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 小米 MiMo ASR 配置
struct XiaomiMiMoASRConfig: Codable, Equatable, Sendable {
    var apiKey: String = ""
    var validationStatus: CloudASRValidationStatus = .unvalidated
    var lastValidationError: String?

    enum CodingKeys: String, CodingKey {
        case apiKey
        case validationStatus
        case lastValidationError
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        validationStatus = try container.decodeIfPresent(CloudASRValidationStatus.self, forKey: .validationStatus) ?? .unvalidated
        lastValidationError = try container.decodeIfPresent(String.self, forKey: .lastValidationError)
    }

    var isComplete: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

extension XiaomiMiMoASRConfig: CloudASRConfigState {
    func incompleteReason(platformName: String) -> String {
        "\(platformName) ASR 配置不完整，请填写 API Key"
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

enum HotkeyKind: String, Codable, Equatable, Sendable {
    case standard
    case special
}

enum HotkeyModifierKey: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case command
    case option
    case control
    case shift

    var genericFlags: NSEvent.ModifierFlags {
        switch self {
        case .command:
            .command
        case .option:
            .option
        case .control:
            .control
        case .shift:
            .shift
        }
    }

    var symbol: String {
        switch self {
        case .command:
            "⌘"
        case .option:
            "⌥"
        case .control:
            "⌃"
        case .shift:
            "⇧"
        }
    }

    var displayName: String {
        switch self {
        case .command:
            "Command"
        case .option:
            "Option"
        case .control:
            "Control"
        case .shift:
            "Shift"
        }
    }

    var shortDisplayName: String {
        symbol
    }

    var sortPriority: Int {
        switch self {
        case .control:
            0
        case .option:
            1
        case .shift:
            2
        case .command:
            3
        }
    }
}

enum HotkeyModifierSide: String, Codable, Equatable, Hashable, Sendable {
    case left
    case right
    case either

    var prefix: String {
        switch self {
        case .left:
            "Left "
        case .right:
            "Right "
        case .either:
            ""
        }
    }

    var shortPrefix: String {
        switch self {
        case .left:
            "L "
        case .right:
            "R "
        case .either:
            ""
        }
    }
}

struct HotkeyModifierSpec: Codable, Equatable, Hashable, Sendable {
    var key: HotkeyModifierKey
    var side: HotkeyModifierSide

    init(key: HotkeyModifierKey, side: HotkeyModifierSide = .either) {
        self.key = key
        self.side = side
    }

    var displayString: String {
        "\(side.shortPrefix)\(key.shortDisplayName)"
    }
}

struct HotkeyCombo: Codable, Equatable, Sendable {
    var kind: HotkeyKind
    var keyCode: UInt16?
    var modifiers: UInt
    var specialModifiers: [HotkeyModifierSpec]
    var displayString: String

    init(
        kind: HotkeyKind,
        keyCode: UInt16?,
        modifiers: UInt,
        specialModifiers: [HotkeyModifierSpec] = [],
        displayString: String
    ) {
        self.kind = kind
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.specialModifiers = specialModifiers.sorted(by: Self.compareModifierSpecs)
        self.displayString = displayString
    }

    init(keyCode: UInt16, modifiers: UInt, displayString: String) {
        self.init(
            kind: .standard,
            keyCode: keyCode,
            modifiers: modifiers,
            displayString: displayString
        )
    }

    static func standard(
        keyCode: UInt16,
        modifiers: UInt,
        keyLabel: String,
        physicalModifiers: [HotkeyModifierSpec] = []
    ) -> HotkeyCombo {
        let sortedPhysicalModifiers = physicalModifiers.sorted(by: compareModifierSpecs)
        return HotkeyCombo(
            kind: .standard,
            keyCode: keyCode,
            modifiers: modifiers,
            specialModifiers: sortedPhysicalModifiers,
            displayString: standardDisplayString(
                modifiers: modifiers,
                physicalModifiers: sortedPhysicalModifiers,
                keyLabel: keyLabel
            )
        )
    }

    static func special(modifiers specs: [HotkeyModifierSpec]) -> HotkeyCombo {
        let sortedSpecs = specs.sorted(by: compareModifierSpecs)
        let genericModifiers = sortedSpecs.reduce(into: NSEvent.ModifierFlags()) { partialResult, spec in
            partialResult.formUnion(spec.key.genericFlags)
        }

        return HotkeyCombo(
            kind: .special,
            keyCode: nil,
            modifiers: genericModifiers.rawValue,
            specialModifiers: sortedSpecs,
            displayString: specialDisplayString(for: sortedSpecs)
        )
    }

    var isPureModifier: Bool {
        kind == .special
    }

    static let `default` = HotkeyCombo(
        keyCode: 49,    // Space
        modifiers: 0x80120, // Option
        displayString: "⌥ + Space"
    )

    private enum CodingKeys: String, CodingKey {
        case kind
        case keyCode
        case modifiers
        case specialModifiers
        case displayString
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedKind = try container.decodeIfPresent(HotkeyKind.self, forKey: .kind)
        let decodedSpecialModifiers = try container.decodeIfPresent([HotkeyModifierSpec].self, forKey: .specialModifiers) ?? []
        let resolvedKind: HotkeyKind = {
            if let decodedKind {
                return decodedKind
            }
            return decodedSpecialModifiers.isEmpty ? .standard : .special
        }()

        let decodedModifiers = try container.decodeIfPresent(UInt.self, forKey: .modifiers) ?? 0
        let decodedDisplayString = try container.decodeIfPresent(String.self, forKey: .displayString)
        let decodedKeyCode = try container.decodeIfPresent(UInt16.self, forKey: .keyCode)

        kind = resolvedKind
        modifiers = decodedModifiers
        specialModifiers = decodedSpecialModifiers.sorted(by: Self.compareModifierSpecs)

        switch resolvedKind {
        case .standard:
            let resolvedKeyCode = decodedKeyCode ?? HotkeyCombo.default.keyCode ?? 49
            keyCode = resolvedKeyCode
            let keyLabel = Self.standardKeyLabel(
                from: decodedDisplayString,
                fallbackKeyCode: resolvedKeyCode
            )
            displayString = Self.standardDisplayString(
                modifiers: decodedModifiers,
                physicalModifiers: decodedSpecialModifiers,
                keyLabel: keyLabel
            )
        case .special:
            keyCode = nil
            displayString = Self.specialDisplayString(for: decodedSpecialModifiers)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(modifiers, forKey: .modifiers)
        try container.encode(displayString, forKey: .displayString)
        if !specialModifiers.isEmpty {
            try container.encode(specialModifiers, forKey: .specialModifiers)
        }
        switch kind {
        case .standard:
            try container.encode(keyCode, forKey: .keyCode)
        case .special:
            break
        }
    }

    private static func standardDisplayString(
        modifiers: UInt,
        physicalModifiers: [HotkeyModifierSpec],
        keyLabel: String
    ) -> String {
        let sortedPhysicalModifiers = physicalModifiers.sorted(by: compareModifierSpecs)
        let coveredKeys = Set(sortedPhysicalModifiers.map(\.key))
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var parts = sortedPhysicalModifiers.map(\.displayString)

        if flags.contains(.control), !coveredKeys.contains(.control) {
            parts.append(HotkeyModifierKey.control.shortDisplayName)
        }
        if flags.contains(.option), !coveredKeys.contains(.option) {
            parts.append(HotkeyModifierKey.option.shortDisplayName)
        }
        if flags.contains(.shift), !coveredKeys.contains(.shift) {
            parts.append(HotkeyModifierKey.shift.shortDisplayName)
        }
        if flags.contains(.command), !coveredKeys.contains(.command) {
            parts.append(HotkeyModifierKey.command.shortDisplayName)
        }
        parts.append(keyLabel)
        return parts.joined(separator: " + ")
    }

    private static func specialDisplayString(for specs: [HotkeyModifierSpec]) -> String {
        specs
            .sorted(by: compareModifierSpecs)
            .map(\.displayString)
            .joined(separator: " + ")
    }

    private static func compareModifierSpecs(_ lhs: HotkeyModifierSpec, _ rhs: HotkeyModifierSpec) -> Bool {
        if lhs.key.sortPriority != rhs.key.sortPriority {
            return lhs.key.sortPriority < rhs.key.sortPriority
        }
        let lhsSide = sidePriority(lhs.side)
        let rhsSide = sidePriority(rhs.side)
        if lhsSide != rhsSide {
            return lhsSide < rhsSide
        }
        return lhs.key.rawValue < rhs.key.rawValue
    }

    private static func sidePriority(_ side: HotkeyModifierSide) -> Int {
        switch side {
        case .either:
            0
        case .left:
            1
        case .right:
            2
        }
    }

    private static func standardKeyLabel(from displayString: String?, fallbackKeyCode: UInt16) -> String {
        guard let displayString else {
            return "Key \(fallbackKeyCode)"
        }

        let trimmed = displayString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Key \(fallbackKeyCode)"
        }

        let symbolSeparated = ["⌘", "⌥", "⌃", "⇧", "+"].reduce(trimmed) { partialResult, token in
            partialResult.replacingOccurrences(of: token, with: " \(token) ")
        }

        let modifierTokens: Set<String> = [
            HotkeyModifierKey.command.symbol,
            HotkeyModifierKey.option.symbol,
            HotkeyModifierKey.control.symbol,
            HotkeyModifierKey.shift.symbol,
            HotkeyModifierKey.command.displayName,
            HotkeyModifierKey.option.displayName,
            HotkeyModifierKey.control.displayName,
            HotkeyModifierKey.shift.displayName,
            HotkeyModifierKey.command.shortDisplayName,
            HotkeyModifierKey.option.shortDisplayName,
            HotkeyModifierKey.control.shortDisplayName,
            HotkeyModifierKey.shift.shortDisplayName,
            "Left",
            "Right",
            "L",
            "R"
        ]

        let keyTokens = symbolSeparated
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { token in
                token != "+"
                    && !modifierTokens.contains(token)
            }

        guard !keyTokens.isEmpty else {
            return "Key \(fallbackKeyCode)"
        }

        return keyTokens.joined(separator: " ")
    }
}
