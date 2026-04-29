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
    case localFunASR = "localFunASR"
    case tencentCloudSentence = "tencentCloudSentence"
}

/// ASR 总配置
struct ASRConfig: Codable, Equatable, Sendable {
    var selectedPlatform: ASRPlatform = .localFunASR
    var local: LocalASRConfig = LocalASRConfig()
    var tencentCloud: TencentASRConfig = TencentASRConfig()
}

/// 本地 FunASR 模型状态
enum LocalModelStatus: String, Codable, Equatable, Sendable {
    case notDownloaded = "notDownloaded"
    case downloading = "downloading"
    case ready = "ready"
    case failed = "failed"
}

/// 本地 ASR 配置
struct LocalASRConfig: Codable, Equatable, Sendable {
    var modelStatus: LocalModelStatus = .notDownloaded
    var lastError: String?
    var mirrorSource: String?

    /// 模型固定版本标识
    static let modelVersion = "1.0.0"

    /// 模型根目录
    static var modelRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".typoless/models/funasr", isDirectory: true)
    }
}

/// 腾讯云一句话识别配置
struct TencentASRConfig: Codable, Equatable, Sendable {
    var secretId: String = ""
    var secretKey: String = ""
}

// MARK: - 通用配置

struct GeneralConfig: Codable, Equatable, Sendable {
    var hotkey: HotkeyCombo = .default
    var pasteboardInjectionBundleIDs: [String] = []

    enum CodingKeys: String, CodingKey {
        case hotkey
        case pasteboardInjectionBundleIDs
    }

    init(
        hotkey: HotkeyCombo = .default,
        pasteboardInjectionBundleIDs: [String] = []
    ) {
        self.hotkey = hotkey
        self.pasteboardInjectionBundleIDs = pasteboardInjectionBundleIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotkey = try container.decodeIfPresent(HotkeyCombo.self, forKey: .hotkey) ?? .default
        pasteboardInjectionBundleIDs = try container.decodeIfPresent([String].self, forKey: .pasteboardInjectionBundleIDs) ?? []
    }

    static let defaultPasteboardInjectionBundleIDs = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.todesktop.230313mzl4w4u92",
        "com.microsoft.VSCode",
        "com.jetbrains.*",
        "abnerworks.Typora"
    ]

    var effectivePasteboardInjectionBundleIDs: [String] {
        Array(Set(Self.defaultPasteboardInjectionBundleIDs + pasteboardInjectionBundleIDs))
            .sorted()
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
