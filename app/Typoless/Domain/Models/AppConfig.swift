import Foundation

// MARK: - LLM 配置（不含密钥）

struct LLMConfig: Codable, Equatable, Sendable {
    var baseURL: String = ""
    var model: String = ""
    var thinkingDisabled: Bool = false
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
