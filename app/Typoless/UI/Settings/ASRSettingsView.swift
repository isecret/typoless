import SwiftUI

struct ASRSettingsView: View {
    let configStore: ConfigStore

    @State private var downloadManager: ModelDownloadManager?
    @State private var validationService: CloudASRValidationService?
    @State private var selectedPlatform: ASRPlatform = .localSenseVoice

    @State private var tencentSecretId: String = ""
    @State private var tencentSecretKey: String = ""

    @State private var aliyunAccessKeyId: String = ""
    @State private var aliyunAccessKeySecret: String = ""
    @State private var aliyunAppKey: String = ""

    @State private var volcengineAPIKey: String = ""

    @State private var xunfeiAppID: String = ""
    @State private var xunfeiAPIKey: String = ""
    @State private var xunfeiAPISecret: String = ""

    @State private var isLoaded = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        SettingsPaneSection {
            SettingsFormRow(title: "语音引擎") {
                HStack(spacing: 4) {
                    Picker("语音引擎", selection: $selectedPlatform) {
                        ForEach(ASRPlatform.allCases, id: \.self) { platform in
                            Text(platform.displayName).tag(platform)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()

                    Link(destination: selectedPlatform.documentationURL) {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 14, weight: .regular))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .accessibilityLabel("打开\(selectedPlatform.displayName)文档")
                    .help("打开\(selectedPlatform.displayName)文档")

                    Spacer(minLength: 0)
                }
                .frame(width: SettingsFormLayout.controlWidth, alignment: .leading)
            }

            switch selectedPlatform {
            case .localSenseVoice:
                localSenseVoicePanel
            case .tencentCloudSentence:
                tencentCloudPanel
            case .aliyunSentence:
                aliyunPanel
            case .volcengineSentence:
                volcenginePanel
            case .xunfeiSentence:
                xunfeiPanel
            }
        } footer: {
            Text(selectedPlatform.cloudConfigSummary)
        }
        .onAppear {
            loadDraft()
            isLoaded = true
        }
        .onDisappear { flushPendingSave() }
        .onChange(of: selectedPlatform) {
            savePlatform()
            validationService?.syncFromConfig(for: currentValidationInput())
        }
        .onChange(of: tencentSecretId) { debouncedSaveCloudConfig() }
        .onChange(of: tencentSecretKey) { debouncedSaveCloudConfig() }
        .onChange(of: aliyunAccessKeyId) { debouncedSaveCloudConfig() }
        .onChange(of: aliyunAccessKeySecret) { debouncedSaveCloudConfig() }
        .onChange(of: aliyunAppKey) { debouncedSaveCloudConfig() }
        .onChange(of: volcengineAPIKey) { debouncedSaveCloudConfig() }
        .onChange(of: xunfeiAppID) { debouncedSaveCloudConfig() }
        .onChange(of: xunfeiAPIKey) { debouncedSaveCloudConfig() }
        .onChange(of: xunfeiAPISecret) { debouncedSaveCloudConfig() }
    }

    // MARK: - Panels

    @ViewBuilder
    private var localSenseVoicePanel: some View {
        let status = configStore.asrConfig.local.modelStatus
        let error = localModelError(for: status)

        SettingsFormRow(title: "引擎状态") {
            VStack(alignment: .trailing, spacing: 4) {
                localModelStatusContent(for: status)

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .frame(width: SettingsFormLayout.controlWidth, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private var tencentCloudPanel: some View {
        cloudField(title: "SecretId", text: $tencentSecretId)
        cloudSecureField(title: "SecretKey", text: $tencentSecretKey)
        cloudStatusRow(for: .tencentCloudSentence)
    }

    @ViewBuilder
    private var aliyunPanel: some View {
        cloudField(title: "AccessKey ID", text: $aliyunAccessKeyId)
        cloudSecureField(title: "AccessKey Secret", text: $aliyunAccessKeySecret)
        cloudField(title: "AppKey", text: $aliyunAppKey)
        cloudStatusRow(for: .aliyunSentence)
    }

    @ViewBuilder
    private var volcenginePanel: some View {
        cloudSecureField(title: "API Key", text: $volcengineAPIKey)
        cloudStatusRow(for: .volcengineSentence)
    }

    @ViewBuilder
    private var xunfeiPanel: some View {
        cloudField(title: "AppID", text: $xunfeiAppID)
        cloudField(title: "API Key", text: $xunfeiAPIKey)
        cloudSecureField(title: "API Secret", text: $xunfeiAPISecret)
        cloudStatusRow(for: .xunfeiSentence)
    }

    // MARK: - Shared Rows

    private func cloudField(title: String, text: Binding<String>) -> some View {
        SettingsFormRow(title: title) {
            SettingsTextInputField(text: text)
        }
    }

    private func cloudSecureField(title: String, text: Binding<String>) -> some View {
        SettingsFormRow(title: title) {
            SettingsSecureInputField(text: text)
        }
    }

    private func cloudStatusRow(for platform: ASRPlatform) -> some View {
        SettingsFormRow(title: "引擎状态") {
            VStack(alignment: .leading, spacing: 4) {
                cloudValidationStatusView(for: platform)

                let draftConfig = currentDraftConfig()
                let persistedError = persistedCloudValidationError(for: platform, in: draftConfig)
                let serviceError = validationService?.lastErrorMessage
                let errorMessage = serviceError?.isEmpty == false ? serviceError : persistedError

                if let errorMessage,
                   persistedCloudValidationState(for: platform, in: draftConfig) == .failed,
                   selectedPlatform == platform,
                   CloudASRValidationInput(platform: platform, asrConfig: draftConfig).isComplete {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .frame(width: SettingsFormLayout.controlWidth, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Local Model

    @ViewBuilder
    private func localModelStatusContent(for status: LocalModelStatus) -> some View {
        switch status {
        case .notDownloaded:
            HStack(spacing: 10) {
                statusIndicator(
                    text: "未就绪",
                    systemImage: "exclamationmark.triangle.fill",
                    color: .orange
                )

                Button("下载") {
                    ensureDownloadManager().startDownload()
                }
                .fixedSize()
            }
            .accessibilityLabel("下载模型")
            .accessibilityValue("未下载")
            .help("下载模型")
        case .downloading:
            if let manager = downloadManager {
                HStack(spacing: 10) {
                    ProgressView(value: manager.progress)
                        .frame(width: 180)

                    Button {
                        manager.cancelDownload()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("取消下载")
                    .accessibilityValue("下载中")
                    .help("取消下载")
                }
            }
        case .ready:
            statusIndicator(
                text: "已就绪",
                systemImage: "checkmark.circle.fill",
                color: .green
            )
                .accessibilityLabel("模型已就绪")
                .accessibilityValue("已就绪")
                .help("模型已就绪")
        case .failed:
            Button("重试下载") {
                ensureDownloadManager().startDownload()
            }
            .fixedSize()
            .accessibilityLabel("重试下载")
            .accessibilityValue("下载失败")
            .help("重试下载")
        }
    }

    private func localModelError(for status: LocalModelStatus) -> String? {
        guard status == .failed else { return nil }
        return configStore.asrConfig.local.lastError ?? downloadManager?.lastError
    }

    // MARK: - Persistence

    private func loadDraft() {
        configStore.refreshLocalModelStatusFromDisk()
        selectedPlatform = configStore.asrConfig.selectedPlatform

        tencentSecretId = configStore.asrConfig.tencentCloud.secretId
        tencentSecretKey = configStore.asrConfig.tencentCloud.secretKey

        aliyunAccessKeyId = configStore.asrConfig.aliyun.accessKeyId
        aliyunAccessKeySecret = configStore.asrConfig.aliyun.accessKeySecret
        aliyunAppKey = configStore.asrConfig.aliyun.appKey

        volcengineAPIKey = configStore.asrConfig.volcengine.apiKey

        xunfeiAppID = configStore.asrConfig.xunfei.appID
        xunfeiAPIKey = configStore.asrConfig.xunfei.apiKey
        xunfeiAPISecret = configStore.asrConfig.xunfei.apiSecret

        downloadManager = ModelDownloadManager(configStore: configStore)
        validationService = CloudASRValidationService(configStore: configStore)
        validationService?.syncFromConfig(for: currentValidationInput())

        if configStore.asrConfig.local.modelStatus == .downloading {
            try? configStore.updateLocalModelStatus(.failed, error: "上次下载被中断")
        }
    }

    private func currentDraftConfig() -> ASRConfig {
        var config = configStore.asrConfig
        config.selectedPlatform = selectedPlatform
        config.tencentCloud.secretId = tencentSecretId.trimmingCharacters(in: .whitespacesAndNewlines)
        config.tencentCloud.secretKey = tencentSecretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        config.aliyun.accessKeyId = aliyunAccessKeyId.trimmingCharacters(in: .whitespacesAndNewlines)
        config.aliyun.accessKeySecret = aliyunAccessKeySecret.trimmingCharacters(in: .whitespacesAndNewlines)
        config.aliyun.appKey = aliyunAppKey.trimmingCharacters(in: .whitespacesAndNewlines)
        config.volcengine.apiKey = volcengineAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        config.xunfei.appID = xunfeiAppID.trimmingCharacters(in: .whitespacesAndNewlines)
        config.xunfei.apiKey = xunfeiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        config.xunfei.apiSecret = xunfeiAPISecret.trimmingCharacters(in: .whitespacesAndNewlines)
        return config
    }

    private func savePlatform() {
        guard isLoaded else { return }
        try? configStore.saveASRConfig(currentDraftConfig())
        validationService?.syncFromConfig(for: currentValidationInput())
    }

    private func debouncedSaveCloudConfig() {
        guard isLoaded else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            saveCloudConfig()
        }
    }

    private func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        if isLoaded { saveCloudConfig() }
    }

    private func saveCloudConfig() {
        let draftConfig = currentDraftConfig()
        try? configStore.saveASRConfig(draftConfig)
        validationService?.syncFromConfig(for: currentValidationInput())

        let input = currentValidationInput()
        if input.isCloudPlatform {
            validationService?.validate(input)
        }
    }

    @discardableResult
    private func ensureDownloadManager() -> ModelDownloadManager {
        if let manager = downloadManager {
            return manager
        }

        let manager = ModelDownloadManager(configStore: configStore)
        downloadManager = manager
        return manager
    }

    @ViewBuilder
    private func statusIndicator(text: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(text)
        }
        .foregroundStyle(color)
    }

    private func currentValidationInput() -> CloudASRValidationInput {
        CloudASRValidationInput(
            platform: selectedPlatform,
            asrConfig: currentDraftConfig()
        )
    }

    @ViewBuilder
    private func cloudValidationStatusView(for platform: ASRPlatform) -> some View {
        if selectedPlatform != platform {
            statusIndicator(text: "未就绪", systemImage: "exclamationmark.triangle.fill", color: .orange)
        } else {
            let draftConfig = currentDraftConfig()
            let isComplete = CloudASRValidationInput(platform: platform, asrConfig: draftConfig).isComplete
            let persistedState = persistedCloudValidationState(for: platform, in: draftConfig)

            switch persistedState {
            case .verified:
                statusIndicator(
                    text: "已就绪",
                    systemImage: "checkmark.circle.fill",
                    color: .green
                )
            case .failed:
                let hasFailureMessage = (validationService?.lastErrorMessage?.isEmpty == false)
                    || !(persistedCloudValidationError(for: platform, in: draftConfig)?.isEmpty ?? true)
                statusIndicator(
                    text: hasFailureMessage && isComplete ? "验证失败" : "未就绪",
                    systemImage: hasFailureMessage && isComplete ? "xmark.circle.fill" : "exclamationmark.triangle.fill",
                    color: hasFailureMessage && isComplete ? .red : .orange
                )
            case .unvalidated, .validating:
                statusIndicator(
                    text: "未就绪",
                    systemImage: "exclamationmark.triangle.fill",
                    color: .orange
                )
            }
        }
    }

    private func persistedCloudValidationState(for platform: ASRPlatform, in config: ASRConfig) -> CloudASRValidationStatus {
        switch platform {
        case .localSenseVoice:
            return .unvalidated
        case .tencentCloudSentence:
            return config.tencentCloud.validationStatus
        case .aliyunSentence:
            return config.aliyun.validationStatus
        case .volcengineSentence:
            return config.volcengine.validationStatus
        case .xunfeiSentence:
            return config.xunfei.validationStatus
        }
    }

    private func persistedCloudValidationError(for platform: ASRPlatform, in config: ASRConfig) -> String? {
        switch platform {
        case .localSenseVoice:
            return nil
        case .tencentCloudSentence:
            return config.tencentCloud.lastValidationError
        case .aliyunSentence:
            return config.aliyun.lastValidationError
        case .volcengineSentence:
            return config.volcengine.lastValidationError
        case .xunfeiSentence:
            return config.xunfei.lastValidationError
        }
    }
}
