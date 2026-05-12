import SwiftUI

struct ASRSettingsView: View {
    let configStore: ConfigStore

    @State private var downloadManager: ModelDownloadManager?
    @State private var selectedPlatform: ASRPlatform = .localFunASR

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
        Section {
            SettingsFormRow(title: "语音引擎") {
                Picker("语音引擎", selection: $selectedPlatform) {
                    ForEach(ASRPlatform.allCases, id: \.self) { platform in
                        Text(platform.displayName).tag(platform)
                    }
                }
                .labelsHidden()
                .frame(width: 320, alignment: .trailing)
            }

            switch selectedPlatform {
            case .localFunASR:
                localFunASRPanel
            case .tencentCloudSentence:
                tencentCloudPanel
            case .aliyunSentence:
                aliyunPanel
            case .volcengineSentence:
                volcenginePanel
            case .xunfeiSentence:
                xunfeiPanel
            }
        } header: {
            Text("语音识别")
        } footer: {
            Text(selectedPlatform.cloudConfigSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            loadDraft()
            isLoaded = true
        }
        .onDisappear { flushPendingSave() }
        .onChange(of: selectedPlatform) {
            savePlatform()
            debouncedSaveCloudConfig()
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
    private var localFunASRPanel: some View {
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
                        .frame(width: 320, alignment: .trailing)
                }
            }
        }
    }

    @ViewBuilder
    private var tencentCloudPanel: some View {
        cloudField(title: "SecretId", text: $tencentSecretId)
        cloudSecureField(title: "SecretKey", text: $tencentSecretKey)
        cloudStatusRow(isReady: currentDraftConfig().tencentCloud.isComplete)
    }

    @ViewBuilder
    private var aliyunPanel: some View {
        cloudField(title: "AccessKey ID", text: $aliyunAccessKeyId)
        cloudSecureField(title: "AccessKey Secret", text: $aliyunAccessKeySecret)
        cloudField(title: "AppKey", text: $aliyunAppKey)
        cloudStatusRow(isReady: currentDraftConfig().aliyun.isComplete)
    }

    @ViewBuilder
    private var volcenginePanel: some View {
        cloudSecureField(title: "API Key", text: $volcengineAPIKey)
        cloudStatusRow(isReady: currentDraftConfig().volcengine.isComplete)
    }

    @ViewBuilder
    private var xunfeiPanel: some View {
        cloudField(title: "AppID", text: $xunfeiAppID)
        cloudField(title: "API Key", text: $xunfeiAPIKey)
        cloudSecureField(title: "API Secret", text: $xunfeiAPISecret)
        cloudStatusRow(isReady: currentDraftConfig().xunfei.isComplete)
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

    private func cloudStatusRow(isReady: Bool) -> some View {
        SettingsFormRow(title: "引擎状态") {
            statusIndicator(
                text: isReady ? "已就绪" : "未就绪",
                systemImage: isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                color: isReady ? .green : .orange
            )
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
        try? configStore.saveASRConfig(currentDraftConfig())
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
}
