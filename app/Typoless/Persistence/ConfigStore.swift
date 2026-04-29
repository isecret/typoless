import Foundation

/// 配置中心：全部配置统一存储到 ~/.typoless/config
@MainActor
@Observable
final class ConfigStore {
    // MARK: - 公开配置

    private(set) var llmConfig = LLMConfig()
    private(set) var generalConfig = GeneralConfig()

    // MARK: - 密钥（启动时从配置文件直接加载到内存）

    private(set) var openAIAPIKey: String = ""

    /// 配置文件加载是否失败（损坏等情况），用于区分 fresh install 与 corrupt config
    private(set) var configLoadFailed: Bool = false

    // MARK: - 首次配置判断

    /// 必填配置是否已就绪
    var hasCompletedInitialSetup: Bool {
        !configLoadFailed
    }

    // MARK: - 配置文件路径

    private static let configDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".typoless", isDirectory: true)
    }()

    private static let configFileURL: URL = {
        configDirectory.appendingPathComponent("config")
    }()

    // MARK: - 旧存储键（仅用于迁移）

    private enum LegacyDefaultsKey {
        static let llmConfig = "typoless.llm_config"
        static let generalConfig = "typoless.general_config"
        static let hasOpenAIAPIKey = "typoless.has_openai_api_key"
    }

    private enum LegacyKeychainAccount {
        static let openAIAPIKey = "openai_api_key"
    }

    // MARK: - 配置文件模型

    private struct ConfigFile: Codable {
        var llm: LLMFileConfig = LLMFileConfig()
        var general: GeneralConfig = GeneralConfig()

        struct LLMFileConfig: Codable {
            var baseURL: String = ""
            var model: String = ""
            var apiKey: String = ""
            var thinkingDisabled: Bool = false
        }
    }

    // MARK: - 初始化

    init() {
        loadAll()
    }

    // MARK: - 加载

    func loadAll() {
        let fileURL = Self.configFileURL

        if FileManager.default.fileExists(atPath: fileURL.path) {
            // 配置文件已存在，尝试加载
            do {
                let data = try Data(contentsOf: fileURL)
                let configFile = try JSONDecoder().decode(ConfigFile.self, from: data)
                applyConfigFile(configFile)
                configLoadFailed = false
            } catch {
                // 文件损坏或解析失败：标记为加载失败，使 hasCompletedInitialSetup 返回 false
                applyConfigFile(ConfigFile())
                configLoadFailed = true
            }
        } else {
            // 配置文件不存在，尝试从旧存储迁移
            let migrated = migrateFromLegacyStorage()
            applyConfigFile(migrated)
            configLoadFailed = false
            // 写入新配置文件（迁移落盘）
            try? writeConfigFile(migrated)
        }
    }

    // MARK: - LLM 配置保存

    func saveLLMConfig(_ config: LLMConfig, apiKey: String) throws {
        let trimmedURL = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if generalConfig.enableAIPolish {
            if trimmedURL.isEmpty { throw ConfigValidationError.emptyField("Base URL") }
            if trimmedKey.isEmpty { throw ConfigValidationError.emptyField("API Key") }
            if trimmedModel.isEmpty { throw ConfigValidationError.emptyField("Model") }

            if URL(string: trimmedURL) == nil {
                throw ConfigValidationError.invalidURL(trimmedURL)
            }
        }

        var normalConfig = config
        normalConfig.baseURL = trimmedURL
        normalConfig.model = trimmedModel
        normalConfig.thinkingDisabled = shouldResetThinkingDisabled(
            baseURL: trimmedURL,
            model: trimmedModel,
            apiKey: trimmedKey
        ) ? false : llmConfig.thinkingDisabled

        var configFile = buildConfigFile()
        configFile.llm = ConfigFile.LLMFileConfig(
            baseURL: trimmedURL,
            model: trimmedModel,
            apiKey: trimmedKey,
            thinkingDisabled: normalConfig.thinkingDisabled
        )
        try writeConfigFile(configFile)

        llmConfig = normalConfig
        openAIAPIKey = trimmedKey
    }

    func markThinkingDisabledForCurrentLLM() throws {
        guard !llmConfig.thinkingDisabled else { return }

        llmConfig.thinkingDisabled = true
        var configFile = buildConfigFile()
        configFile.llm.thinkingDisabled = true
        try writeConfigFile(configFile)
    }

    // MARK: - 通用配置保存

    func saveGeneralConfig(_ config: GeneralConfig) throws {
        var configFile = buildConfigFile()
        configFile.general = config
        try writeConfigFile(configFile)

        generalConfig = config
    }

    // MARK: - 内部方法

    /// 将 ConfigFile 映射到公开属性
    private func applyConfigFile(_ configFile: ConfigFile) {
        llmConfig = LLMConfig(
            baseURL: configFile.llm.baseURL,
            model: configFile.llm.model,
            thinkingDisabled: configFile.llm.thinkingDisabled
        )
        openAIAPIKey = configFile.llm.apiKey

        generalConfig = configFile.general
    }

    /// 从当前内存状态构建 ConfigFile
    private func buildConfigFile() -> ConfigFile {
        ConfigFile(
            llm: ConfigFile.LLMFileConfig(
                baseURL: llmConfig.baseURL,
                model: llmConfig.model,
                apiKey: openAIAPIKey,
                thinkingDisabled: llmConfig.thinkingDisabled
            ),
            general: generalConfig
        )
    }

    private func shouldResetThinkingDisabled(baseURL: String, model: String, apiKey: String) -> Bool {
        llmConfig.baseURL != baseURL
            || llmConfig.model != model
            || openAIAPIKey != apiKey
    }

    /// 原子写入配置文件，确保目录和文件权限正确
    private func writeConfigFile(_ configFile: ConfigFile) throws {
        let fm = FileManager.default
        let dirURL = Self.configDirectory
        let fileURL = Self.configFileURL

        // 确保目录存在且权限为 0700
        if !fm.fileExists(atPath: dirURL.path) {
            try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dirURL.path)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configFile)

        try data.write(to: fileURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    // MARK: - 旧存储迁移

    /// 从 UserDefaults + Keychain 读取旧配置，若新文件不存在时自动调用
    private func migrateFromLegacyStorage() -> ConfigFile {
        var configFile = ConfigFile()
        let defaults = UserDefaults.standard

        // LLM 普通配置
        if let data = defaults.data(forKey: LegacyDefaultsKey.llmConfig),
           let config = try? JSONDecoder().decode(LLMConfig.self, from: data) {
            configFile.llm.baseURL = config.baseURL
            configFile.llm.model = config.model
        }

        // LLM 密钥
        if defaults.bool(forKey: LegacyDefaultsKey.hasOpenAIAPIKey) {
            configFile.llm.apiKey = KeychainHelper.load(for: LegacyKeychainAccount.openAIAPIKey) ?? ""
        }

        // 通用配置
        if let data = defaults.data(forKey: LegacyDefaultsKey.generalConfig),
           let config = try? JSONDecoder().decode(GeneralConfig.self, from: data) {
            configFile.general = config
        }

        return configFile
    }
}
