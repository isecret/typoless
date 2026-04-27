import Foundation

/// 配置中心：普通设置存 UserDefaults，敏感密钥存 Keychain
@MainActor
@Observable
final class ConfigStore {
    // MARK: - 公开配置（非密钥）

    private(set) var asrConfig = ASRConfig()
    private(set) var llmConfig = LLMConfig()
    private(set) var generalConfig = GeneralConfig()

    // MARK: - 密钥（仅内存缓存，持久化在 Keychain）

    private(set) var tencentSecretId: String = ""
    private(set) var tencentSecretKey: String = ""
    private(set) var openAIAPIKey: String = ""
    private var hasLoadedASRSecrets = false
    private var hasLoadedLLMSecret = false

    // MARK: - 首次配置判断

    /// 必填配置是否已就绪（ASR 密钥 + Region）
    var hasCompletedInitialSetup: Bool {
        let defaults = UserDefaults.standard
        return defaults.bool(forKey: DefaultsKey.hasTencentSecretId)
            && defaults.bool(forKey: DefaultsKey.hasTencentSecretKey)
    }

    // MARK: - UserDefaults Keys

    private enum DefaultsKey {
        static let asrConfig = "typoless.asr_config"
        static let llmConfig = "typoless.llm_config"
        static let generalConfig = "typoless.general_config"
        static let hasTencentSecretId = "typoless.has_tencent_secret_id"
        static let hasTencentSecretKey = "typoless.has_tencent_secret_key"
        static let hasOpenAIAPIKey = "typoless.has_openai_api_key"
    }

    // MARK: - Keychain Accounts

    private enum KeychainAccount {
        static let tencentSecretId = "tencent_secret_id"
        static let tencentSecretKey = "tencent_secret_key"
        static let openAIAPIKey = "openai_api_key"
    }

    // MARK: - 初始化

    init() {
        loadAll()
    }

    // MARK: - 加载

    func loadAll() {
        // UserDefaults
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: DefaultsKey.asrConfig),
           let config = try? JSONDecoder().decode(ASRConfig.self, from: data) {
            asrConfig = config
        }
        if let data = defaults.data(forKey: DefaultsKey.llmConfig),
           let config = try? JSONDecoder().decode(LLMConfig.self, from: data) {
            llmConfig = config
        }
        if let data = defaults.data(forKey: DefaultsKey.generalConfig),
           let config = try? JSONDecoder().decode(GeneralConfig.self, from: data) {
            generalConfig = config
        }

        // Keychain 改为按需加载，避免应用启动即触发钥匙串弹窗
        tencentSecretId = ""
        tencentSecretKey = ""
        openAIAPIKey = ""
        hasLoadedASRSecrets = false
        hasLoadedLLMSecret = false
    }

    func loadASRSecretsIfNeeded() {
        guard !hasLoadedASRSecrets else { return }
        tencentSecretId = KeychainHelper.load(for: KeychainAccount.tencentSecretId) ?? ""
        tencentSecretKey = KeychainHelper.load(for: KeychainAccount.tencentSecretKey) ?? ""
        hasLoadedASRSecrets = true
    }

    func loadLLMSecretIfNeeded() {
        guard !hasLoadedLLMSecret else { return }
        openAIAPIKey = KeychainHelper.load(for: KeychainAccount.openAIAPIKey) ?? ""
        hasLoadedLLMSecret = true
    }

    // MARK: - ASR 配置保存

    func saveASRConfig(_ config: ASRConfig, secretId: String, secretKey: String) throws {
        // 轻量校验
        let trimmedId = secretId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedId.isEmpty { throw ConfigValidationError.emptyField("SecretId") }
        if trimmedKey.isEmpty { throw ConfigValidationError.emptyField("SecretKey") }

        // 保存普通配置到 UserDefaults
        let data = try JSONEncoder().encode(config)
        UserDefaults.standard.set(data, forKey: DefaultsKey.asrConfig)

        // 保存密钥到 Keychain
        try KeychainHelper.save(trimmedId, for: KeychainAccount.tencentSecretId)
        try KeychainHelper.save(trimmedKey, for: KeychainAccount.tencentSecretKey)
        UserDefaults.standard.set(!trimmedId.isEmpty, forKey: DefaultsKey.hasTencentSecretId)
        UserDefaults.standard.set(!trimmedKey.isEmpty, forKey: DefaultsKey.hasTencentSecretKey)

        // 更新内存
        asrConfig = config
        tencentSecretId = trimmedId
        tencentSecretKey = trimmedKey
        hasLoadedASRSecrets = true
    }

    // MARK: - LLM 配置保存

    func saveLLMConfig(_ config: LLMConfig, apiKey: String) throws {
        let trimmedURL = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        // 仅在 AI 润色开启时做必填校验
        if generalConfig.enableAIPolish {
            if trimmedURL.isEmpty { throw ConfigValidationError.emptyField("Base URL") }
            if trimmedKey.isEmpty { throw ConfigValidationError.emptyField("API Key") }
            if trimmedModel.isEmpty { throw ConfigValidationError.emptyField("Model") }

            // URL 格式校验
            if URL(string: trimmedURL) == nil {
                throw ConfigValidationError.invalidURL(trimmedURL)
            }
        }

        // 保存普通配置到 UserDefaults
        var normalConfig = config
        normalConfig.baseURL = trimmedURL
        normalConfig.model = trimmedModel
        let data = try JSONEncoder().encode(normalConfig)
        UserDefaults.standard.set(data, forKey: DefaultsKey.llmConfig)

        // 保存密钥到 Keychain（即使为空也更新）
        if !trimmedKey.isEmpty {
            try KeychainHelper.save(trimmedKey, for: KeychainAccount.openAIAPIKey)
        }
        UserDefaults.standard.set(!trimmedKey.isEmpty, forKey: DefaultsKey.hasOpenAIAPIKey)

        // 更新内存
        llmConfig = normalConfig
        openAIAPIKey = trimmedKey
        hasLoadedLLMSecret = true
    }

    // MARK: - 通用配置保存

    func saveGeneralConfig(_ config: GeneralConfig) throws {
        let data = try JSONEncoder().encode(config)
        UserDefaults.standard.set(data, forKey: DefaultsKey.generalConfig)
        generalConfig = config
    }
}
