import Foundation

/// 配置中心：全部配置统一存储到 ~/.typoless/config.json
@MainActor
@Observable
final class ConfigStore {
    // MARK: - 公开配置

    private(set) var llmConfig = LLMConfig()
    private(set) var generalConfig = GeneralConfig()
    private(set) var asrConfig = ASRConfig()
    private(set) var audioInputConfig = AudioInputConfig.systemDefault
    private(set) var legacyAutomaticUpdateChecksEnabled: Bool?

    // MARK: - 密钥（启动时从配置文件直接加载到内存）

    private(set) var openAIAPIKey: String = ""

    /// 配置文件加载是否失败（损坏等情况），用于区分 fresh install 与 corrupt config
    private(set) var configLoadFailed: Bool = false

    // MARK: - 首次配置判断

    /// 必填配置是否已就绪
    var hasCompletedInitialSetup: Bool {
        !configLoadFailed
    }

    var isLLMConfigured: Bool {
        !llmConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !llmConfig.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 当前选中的 ASR 平台是否可用
    var isASRReady: Bool {
        asrConfig.isReady(localModelsAvailable: Self.localModelsAvailable())
    }

    /// ASR 平台不可用的原因描述
    var asrNotReadyReason: String? {
        asrConfig.notReadyReason(localModelsAvailable: Self.localModelsAvailable())
    }

    // MARK: - 配置文件路径

    private let configDirectory: URL
    private let configFileURL: URL

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
        var general: GeneralFileConfig = GeneralFileConfig()
        var asr: ASRConfig = ASRConfig()
        var audio: AudioInputConfig = .systemDefault

        enum CodingKeys: String, CodingKey {
            case llm
            case general
            case asr
            case audio
        }

        init(
            llm: LLMFileConfig = LLMFileConfig(),
            general: GeneralFileConfig = GeneralFileConfig(),
            asr: ASRConfig = ASRConfig(),
            audio: AudioInputConfig = .systemDefault
        ) {
            self.llm = llm
            self.general = general
            self.asr = asr
            self.audio = audio
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            llm = try container.decodeIfPresent(LLMFileConfig.self, forKey: .llm) ?? LLMFileConfig()
            general = try container.decodeIfPresent(GeneralFileConfig.self, forKey: .general) ?? GeneralFileConfig()
            asr = try container.decodeIfPresent(ASRConfig.self, forKey: .asr) ?? ASRConfig()
            audio = try container.decodeIfPresent(AudioInputConfig.self, forKey: .audio) ?? .systemDefault
        }

        struct LLMFileConfig: Codable {
            var baseURL: String = ""
            var model: String = ""
            var apiKey: String = ""
            var thinkingDisabled: Bool = false
        }

        struct GeneralFileConfig: Codable {
            var hotkey: HotkeyCombo = .default
            var interactionSoundEnabled: Bool = true
            var automaticUpdateChecksEnabled: Bool?
            var translationTargetLanguage: TranslationTargetLanguage = .english
            var launchAtLogin: Bool = false

            enum CodingKeys: String, CodingKey {
                case hotkey
                case interactionSoundEnabled
                case automaticUpdateChecksEnabled
                case translationTargetLanguage
                case launchAtLogin
            }

            init(
                hotkey: HotkeyCombo = .default,
                interactionSoundEnabled: Bool = true,
                automaticUpdateChecksEnabled: Bool? = nil,
                translationTargetLanguage: TranslationTargetLanguage = .english,
                launchAtLogin: Bool = false
            ) {
                self.hotkey = hotkey
                self.interactionSoundEnabled = interactionSoundEnabled
                self.automaticUpdateChecksEnabled = automaticUpdateChecksEnabled
                self.translationTargetLanguage = translationTargetLanguage
                self.launchAtLogin = launchAtLogin
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                hotkey = try container.decodeIfPresent(HotkeyCombo.self, forKey: .hotkey) ?? .default
                interactionSoundEnabled = try container.decodeIfPresent(Bool.self, forKey: .interactionSoundEnabled) ?? true
                automaticUpdateChecksEnabled = try container.decodeIfPresent(Bool.self, forKey: .automaticUpdateChecksEnabled)
                translationTargetLanguage = try container.decodeIfPresent(TranslationTargetLanguage.self, forKey: .translationTargetLanguage) ?? .english
                launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(hotkey, forKey: .hotkey)
                try container.encode(interactionSoundEnabled, forKey: .interactionSoundEnabled)
                try container.encode(translationTargetLanguage, forKey: .translationTargetLanguage)
                try container.encode(launchAtLogin, forKey: .launchAtLogin)
            }

            var publicConfig: GeneralConfig {
                GeneralConfig(
                    hotkey: hotkey,
                    interactionSoundEnabled: interactionSoundEnabled,
                    translationTargetLanguage: translationTargetLanguage,
                    launchAtLogin: launchAtLogin
                )
            }
        }
    }

    // MARK: - 初始化

    init(configDirectory: URL? = nil) {
        self.configDirectory = configDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".typoless", isDirectory: true)
        self.configFileURL = self.configDirectory.appendingPathComponent("config.json")
        loadAll()
    }

    // MARK: - 加载

    func loadAll() {
        let fileURL = configFileURL

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

        refreshLocalModelStatusFromDisk()
    }

    // MARK: - LLM 配置保存

    func saveLLMConfig(_ config: LLMConfig, apiKey: String) throws {
        let trimmedURL = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedURL.isEmpty, URL(string: trimmedURL) == nil {
            throw ConfigValidationError.invalidURL(trimmedURL)
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
        configFile.general = ConfigFile.GeneralFileConfig(
            hotkey: config.hotkey,
            interactionSoundEnabled: config.interactionSoundEnabled,
            translationTargetLanguage: config.translationTargetLanguage,
            launchAtLogin: config.launchAtLogin
        )
        try writeConfigFile(configFile)

        generalConfig = config
    }

    // MARK: - ASR 配置保存

    func saveASRConfig(_ config: ASRConfig) throws {
        var normalizedConfig = config
        invalidateCloudValidationStateIfNeeded(from: asrConfig, to: &normalizedConfig)

        var configFile = buildConfigFile()
        configFile.asr = normalizedConfig
        try writeConfigFile(configFile)

        asrConfig = normalizedConfig
    }

    // MARK: - 音频输入配置保存

    func saveAudioInputConfig(_ config: AudioInputConfig) throws {
        var configFile = buildConfigFile()
        configFile.audio = config
        try writeConfigFile(configFile)

        audioInputConfig = config
    }

    func updateLocalModelStatus(_ status: LocalModelStatus, error: String? = nil) throws {
        asrConfig.local.modelStatus = status
        asrConfig.local.lastError = error
        var configFile = buildConfigFile()
        configFile.asr = asrConfig
        try writeConfigFile(configFile)
    }

    func updateCloudValidationState(
        for platform: ASRPlatform,
        status: CloudASRValidationStatus,
        error: String? = nil
    ) throws {
        var updatedConfig = asrConfig

        switch platform {
        case .localSenseVoice:
            return
        case .tencentCloudSentence:
            updatedConfig.tencentCloud.validationStatus = status
            updatedConfig.tencentCloud.lastValidationError = error
        case .aliyunSentence:
            updatedConfig.aliyun.validationStatus = status
            updatedConfig.aliyun.lastValidationError = error
        case .volcengineSentence:
            updatedConfig.volcengine.validationStatus = status
            updatedConfig.volcengine.lastValidationError = error
        case .xunfeiSentence:
            updatedConfig.xunfei.validationStatus = status
            updatedConfig.xunfei.lastValidationError = error
        case .xiaomiMiMoASR:
            updatedConfig.xiaomiMiMo.validationStatus = status
            updatedConfig.xiaomiMiMo.lastValidationError = error
        }

        var configFile = buildConfigFile()
        configFile.asr = updatedConfig
        try writeConfigFile(configFile)
        asrConfig = updatedConfig
    }

    func refreshLocalModelStatusFromDisk() {
        guard asrConfig.local.modelStatus != .downloading else { return }

        let hasLocalModels = Self.localModelsAvailable()
        let currentStatus = asrConfig.local.modelStatus

        if hasLocalModels, currentStatus != .ready {
            try? updateLocalModelStatus(.ready)
        } else if !hasLocalModels, currentStatus == .ready {
            try? updateLocalModelStatus(.notDownloaded)
        }
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

        generalConfig = configFile.general.publicConfig
        legacyAutomaticUpdateChecksEnabled = configFile.general.automaticUpdateChecksEnabled
        asrConfig = normalizedInterruptedCloudValidationStates(in: configFile.asr)
        audioInputConfig = configFile.audio
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
            general: ConfigFile.GeneralFileConfig(
                hotkey: generalConfig.hotkey,
                interactionSoundEnabled: generalConfig.interactionSoundEnabled,
                translationTargetLanguage: generalConfig.translationTargetLanguage,
                launchAtLogin: generalConfig.launchAtLogin
            ),
            asr: asrConfig,
            audio: audioInputConfig
        )
    }

    private func shouldResetThinkingDisabled(baseURL: String, model: String, apiKey: String) -> Bool {
        llmConfig.baseURL != baseURL
            || llmConfig.model != model
            || openAIAPIKey != apiKey
    }

    private func invalidateCloudValidationStateIfNeeded(from oldConfig: ASRConfig, to newConfig: inout ASRConfig) {
        if oldConfig.tencentCloud.secretId != newConfig.tencentCloud.secretId
            || oldConfig.tencentCloud.secretKey != newConfig.tencentCloud.secretKey {
            newConfig.tencentCloud.validationStatus = .unvalidated
            newConfig.tencentCloud.lastValidationError = nil
        }

        if oldConfig.aliyun.accessKeyId != newConfig.aliyun.accessKeyId
            || oldConfig.aliyun.accessKeySecret != newConfig.aliyun.accessKeySecret
            || oldConfig.aliyun.appKey != newConfig.aliyun.appKey {
            newConfig.aliyun.validationStatus = .unvalidated
            newConfig.aliyun.lastValidationError = nil
        }

        if oldConfig.volcengine.apiKey != newConfig.volcengine.apiKey {
            newConfig.volcengine.validationStatus = .unvalidated
            newConfig.volcengine.lastValidationError = nil
        }

        if oldConfig.xunfei.appID != newConfig.xunfei.appID
            || oldConfig.xunfei.apiKey != newConfig.xunfei.apiKey
            || oldConfig.xunfei.apiSecret != newConfig.xunfei.apiSecret {
            newConfig.xunfei.validationStatus = .unvalidated
            newConfig.xunfei.lastValidationError = nil
        }

        if oldConfig.xiaomiMiMo.apiKey != newConfig.xiaomiMiMo.apiKey {
            newConfig.xiaomiMiMo.validationStatus = .unvalidated
            newConfig.xiaomiMiMo.lastValidationError = nil
        }
    }

    private func normalizedInterruptedCloudValidationStates(in config: ASRConfig) -> ASRConfig {
        var normalized = config

        if normalized.tencentCloud.validationStatus == .validating {
            normalized.tencentCloud.validationStatus = .unvalidated
            normalized.tencentCloud.lastValidationError = nil
        }

        if normalized.aliyun.validationStatus == .validating {
            normalized.aliyun.validationStatus = .unvalidated
            normalized.aliyun.lastValidationError = nil
        }

        if normalized.volcengine.validationStatus == .validating {
            normalized.volcengine.validationStatus = .unvalidated
            normalized.volcengine.lastValidationError = nil
        }

        if normalized.xunfei.validationStatus == .validating {
            normalized.xunfei.validationStatus = .unvalidated
            normalized.xunfei.lastValidationError = nil
        }

        if normalized.xiaomiMiMo.validationStatus == .validating {
            normalized.xiaomiMiMo.validationStatus = .unvalidated
            normalized.xiaomiMiMo.lastValidationError = nil
        }

        return normalized
    }

    private static func localModelsAvailable() -> Bool {
        let fm = FileManager.default

        for fileName in LocalASRConfig.requiredFileNames {
            let fileURL = LocalASRConfig.modelRoot.appendingPathComponent(fileName)
            guard fm.fileExists(atPath: fileURL.path),
                  ((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0 else {
                return false
            }
        }

        return true
    }

    /// 原子写入配置文件，确保目录和文件权限正确
    private func writeConfigFile(_ configFile: ConfigFile) throws {
        let fm = FileManager.default
        let dirURL = configDirectory
        let fileURL = configFileURL

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
           let config = try? JSONDecoder().decode(ConfigFile.GeneralFileConfig.self, from: data) {
            configFile.general = config
        }

        return configFile
    }
}
