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
            // 平台选择
            Picker("识别平台", selection: $selectedPlatform) {
                Text("本地 FunASR").tag(ASRPlatform.localFunASR)
                Text("腾讯云一句话识别").tag(ASRPlatform.tencentCloudSentence)
            }
            .pickerStyle(.segmented)

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

        LabeledContent("模型状态") {
            HStack(spacing: 6) {
                statusIcon(for: status)
                Text(statusText(for: status))
                    .foregroundStyle(statusColor(for: status))
            }
        }

        if let manager = downloadManager, manager.isDownloading {
            LabeledContent("下载进度") {
                HStack(spacing: 8) {
                    ProgressView(value: manager.progress)
                        .frame(width: 160)
                    Text("\(Int(manager.progress * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                    Button("取消") {
                        manager.cancelDownload()
                    }
                    .controlSize(.small)
                }
            }
        } else {
            LabeledContent("操作") {
                HStack(spacing: 8) {
                    switch status {
                    case .notDownloaded, .failed:
                        Button("下载模型") {
                            ensureDownloadManager().startDownload()
                        }
                    case .ready:
                        Button("重新下载") {
                            ensureDownloadManager().redownload()
                        }
                        Button("删除模型", role: .destructive) {
                            ensureDownloadManager().deleteModels()
                        }
                    case .downloading:
                        EmptyView()
                    }
                }
                .controlSize(.small)
            }
        }

        if let error = configStore.asrConfig.local.lastError ?? downloadManager?.lastError {
            LabeledContent("错误") {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(width: 320, alignment: .leading)
            }
        }

        LabeledContent("模型路径") {
            Text(LocalASRConfig.modelRoot.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 320, alignment: .leading)
        }

        LabeledContent("模型版本") {
            Text("v\(LocalASRConfig.modelVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 腾讯云面板

    @ViewBuilder
    private var tencentCloudPanel: some View {
        LabeledContent("SecretId") {
            TextField("", text: $secretId)
                .settingsASRInputStyle()
        }

        LabeledContent("SecretKey") {
            SecureField("", text: $secretKey)
                .settingsASRInputStyle()
        }

        LabeledContent("配置状态") {
            if configStore.isASRReady && selectedPlatform == .tencentCloudSentence {
                Label("已配置", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else {
                Label("未配置", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
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
            Text("腾讯云模式：语音数据会发送到腾讯云进行识别。请确保已了解相关隐私政策。")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    // MARK: - 状态辅助

    private func statusIcon(for status: LocalModelStatus) -> some View {
        Group {
            switch status {
            case .notDownloaded:
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.secondary)
            case .downloading:
                Image(systemName: "arrow.down.circle.dotted")
                    .foregroundStyle(.blue)
            case .ready:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private func statusText(for status: LocalModelStatus) -> String {
        switch status {
        case .notDownloaded: return "未下载"
        case .downloading: return "下载中"
        case .ready: return "已就绪"
        case .failed: return "下载失败"
        }
    }

    private func statusColor(for status: LocalModelStatus) -> Color {
        switch status {
        case .notDownloaded: return .secondary
        case .downloading: return .blue
        case .ready: return .green
        case .failed: return .red
        }
    }

    // MARK: - 保存逻辑

    private func loadDraft() {
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
}

// MARK: - Style Helpers

private extension View {
    func settingsASRInputStyle() -> some View {
        frame(width: 320)
            .lineLimit(1)
            .truncationMode(.tail)
            .textFieldStyle(.roundedBorder)
            .controlSize(.regular)
            .frame(height: 28)
    }
}
