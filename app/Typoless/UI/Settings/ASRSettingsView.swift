import SwiftUI

struct ASRSettingsView: View {
    let configStore: ConfigStore

    @State private var provider: ASRProviderType = .funasrLocal
    @State private var secretId: String = ""
    @State private var secretKey: String = ""
    @State private var region: TencentRegion = .guangzhou
    @State private var isLoaded = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        Section {
            Picker("识别方式", selection: $provider) {
                ForEach(ASRProviderType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
        } header: {
            Text("语音识别")
        }

        if provider == .funasrLocal {
            Section {
                Text("使用内置本地识别，无需额外配置")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } header: {
                Text("本地识别")
            }
        }

        if provider == .tencentCloud {
            Section {
                LabeledContent("SecretId") {
                    TextField("", text: $secretId)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("SecretKey") {
                    SecureField("", text: $secretKey)
                        .textFieldStyle(.roundedBorder)
                }
            } header: {
                Text("腾讯云凭证")
            }

            Section {
                Picker("地域", selection: $region) {
                    ForEach(TencentRegion.allCases, id: \.self) { r in
                        Text(r.displayName).tag(r)
                    }
                }
            } header: {
                Text("服务地域")
            }
        }

        EmptyView()
            .onAppear {
                loadDraft()
                isLoaded = true
            }
            .onDisappear { flushPendingSave() }
            .onChange(of: provider) { immediateSave() }
            .onChange(of: secretId) { debouncedSave() }
            .onChange(of: secretKey) { debouncedSave() }
            .onChange(of: region) { immediateSave() }
    }

    private func loadDraft() {
        provider = configStore.asrConfig.provider
        secretId = configStore.tencentSecretId
        secretKey = configStore.tencentSecretKey
        region = configStore.asrConfig.region
    }

    private func debouncedSave() {
        guard isLoaded else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            trySave()
        }
    }

    private func immediateSave() {
        guard isLoaded else { return }
        trySave()
    }

    private func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        if isLoaded { trySave() }
    }

    private func trySave() {
        let config = ASRConfig(provider: provider, region: region)
        try? configStore.saveASRConfig(config, secretId: secretId, secretKey: secretKey)
    }
}
