import SwiftUI

struct ASRSettingsView: View {
    let configStore: ConfigStore

    @State private var secretId: String = ""
    @State private var secretKey: String = ""
    @State private var region: TencentRegion = .guangzhou
    @State private var isLoaded = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        Section {
            TextField("SecretId", text: $secretId)
                .textFieldStyle(.roundedBorder)
            SecureField("SecretKey", text: $secretKey)
                .textFieldStyle(.roundedBorder)
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
        .onAppear {
            loadDraft()
            isLoaded = true
        }
        .onDisappear { flushPendingSave() }
        .onChange(of: secretId) { debouncedSave() }
        .onChange(of: secretKey) { debouncedSave() }
        .onChange(of: region) { immediateSave() }
    }

    private func loadDraft() {
        configStore.loadASRSecretsIfNeeded()
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
        let config = ASRConfig(region: region)
        try? configStore.saveASRConfig(config, secretId: secretId, secretKey: secretKey)
    }
}
