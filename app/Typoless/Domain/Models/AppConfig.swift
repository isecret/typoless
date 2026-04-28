import Foundation

// MARK: - ASR 配置（不含密钥）

struct ASRConfig: Codable, Equatable, Sendable {
    var region: TencentRegion = .guangzhou
}

enum TencentRegion: String, Codable, CaseIterable, Sendable {
    case guangzhou = "ap-guangzhou"
    case shanghai = "ap-shanghai"
    case beijing = "ap-beijing"
    case chengdu = "ap-chengdu"
    case chongqing = "ap-chongqing"

    var displayName: String {
        switch self {
        case .guangzhou: "华南地区(广州)"
        case .shanghai: "华东地区(上海)"
        case .beijing: "华北地区(北京)"
        case .chengdu: "西南地区(成都)"
        case .chongqing: "西南地区(重庆)"
        }
    }
}

// MARK: - LLM 配置（不含密钥）

struct LLMConfig: Codable, Equatable, Sendable {
    var baseURL: String = ""
    var model: String = ""
}

// MARK: - 通用配置

struct GeneralConfig: Codable, Equatable, Sendable {
    var hotkey: HotkeyCombo = .default
    var enableAIPolish: Bool = true
    var pasteboardInjectionBundleIDs: [String] = []

    enum CodingKeys: String, CodingKey {
        case hotkey
        case enableAIPolish
        case pasteboardInjectionBundleIDs
    }

    init(
        hotkey: HotkeyCombo = .default,
        enableAIPolish: Bool = true,
        pasteboardInjectionBundleIDs: [String] = []
    ) {
        self.hotkey = hotkey
        self.enableAIPolish = enableAIPolish
        self.pasteboardInjectionBundleIDs = pasteboardInjectionBundleIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotkey = try container.decodeIfPresent(HotkeyCombo.self, forKey: .hotkey) ?? .default
        enableAIPolish = try container.decodeIfPresent(Bool.self, forKey: .enableAIPolish) ?? true
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
