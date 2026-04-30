import SwiftUI

struct ASRSettingsView: View {
    let configStore: ConfigStore
    @State private var downloadManager: ModelDownloadManager?

    @State private var selectedPlatform: ASRPlatform = .localFunASR
    @State private var secretId: String = ""
    @State private var secretKey: String = ""
    @State private var isLoaded = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        Section {
            SettingsFormRow(title: "语音引擎") {
                Picker("语音引擎", selection: $selectedPlatform) {
                    Text("本地").tag(ASRPlatform.localFunASR)
                    Text("腾讯云").tag(ASRPlatform.tencentCloudSentence)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 220, alignment: .trailing)
            }

            // 根据选中平台显示对应面板
            switch selectedPlatform {
            case .localFunASR:
                localFunASRPanel
            case .tencentCloudSentence:
                tencentCloudPanel
            }
        } header: {
            Text("语音识别")
        } footer: {
            privacyFooter
        }
        .onAppear {
            loadDraft()
            isLoaded = true
        }
        .onDisappear { flushPendingSave() }
        .onChange(of: selectedPlatform) { savePlatform() }
        .onChange(of: secretId) { debouncedSaveTencentConfig() }
        .onChange(of: secretKey) { debouncedSaveTencentConfig() }
    }

    // MARK: - 本地 FunASR 面板

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

    // MARK: - 腾讯云面板

    @ViewBuilder
    private var tencentCloudPanel: some View {
        SettingsFormRow(title: "SecretId") {
            SettingsTextInputField(text: $secretId)
        }

        SettingsFormRow(title: "SecretKey") {
            SettingsSecureInputField(text: $secretKey)
        }

        SettingsFormRow(title: "引擎状态") {
            if configStore.isASRReady && selectedPlatform == .tencentCloudSentence {
                statusIndicator(
                    text: "已就绪",
                    systemImage: "checkmark.circle.fill",
                    color: .green
                )
            } else {
                statusIndicator(
                    text: "未就绪",
                    systemImage: "exclamationmark.triangle.fill",
                    color: .orange
                )
            }
        }
    }

    // MARK: - 隐私提示

    @ViewBuilder
    private var privacyFooter: some View {
        switch selectedPlatform {
        case .localFunASR:
            Text("本地模式：语音数据仅在本机处理，不会发送到云端 ASR 服务。")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .tencentCloudSentence:
            Text("腾讯云模式：用于一句话识别。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 状态辅助

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

    // MARK: - 保存逻辑

    private func loadDraft() {
        configStore.refreshLocalModelStatusFromDisk()
        selectedPlatform = configStore.asrConfig.selectedPlatform
        secretId = configStore.asrConfig.tencentCloud.secretId
        secretKey = configStore.asrConfig.tencentCloud.secretKey

        // 初始化 download manager
        downloadManager = ModelDownloadManager(configStore: configStore)

        // 如果本地状态是 downloading 但应用刚启动，纠正为 failed
        if configStore.asrConfig.local.modelStatus == .downloading {
            try? configStore.updateLocalModelStatus(.failed, error: "上次下载被中断")
        }
    }

    private func savePlatform() {
        guard isLoaded else { return }
        var config = configStore.asrConfig
        config.selectedPlatform = selectedPlatform
        try? configStore.saveASRConfig(config)
    }

    private func debouncedSaveTencentConfig() {
        guard isLoaded else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            saveTencentConfig()
        }
    }

    private func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        if isLoaded { saveTencentConfig() }
    }

    private func saveTencentConfig() {
        var config = configStore.asrConfig
        config.tencentCloud.secretId = secretId.trimmingCharacters(in: .whitespacesAndNewlines)
        config.tencentCloud.secretKey = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        try? configStore.saveASRConfig(config)
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
