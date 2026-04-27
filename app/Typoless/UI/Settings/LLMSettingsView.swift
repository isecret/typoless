import SwiftUI

struct LLMSettingsView: View {
    let configStore: ConfigStore

    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var model: String = ""
    @State private var isLoaded = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        Section {
            TextField("Base URL", text: $baseURL)
                .textFieldStyle(.roundedBorder)
            SecureField("API Key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
            TextField("Model", text: $model)
                .textFieldStyle(.roundedBorder)
        } header: {
            Text("OpenAI 兼容接口")
        } footer: {
            Text("支持任何兼容 OpenAI Chat Completions 的接口")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            loadDraft()
            isLoaded = true
        }
        .onDisappear { flushPendingSave() }
        .onChange(of: baseURL) { debouncedSave() }
        .onChange(of: apiKey) { debouncedSave() }
        .onChange(of: model) { debouncedSave() }
    }

    private func loadDraft() {
        configStore.loadLLMSecretIfNeeded()
        baseURL = configStore.llmConfig.baseURL
        apiKey = configStore.openAIAPIKey
        model = configStore.llmConfig.model
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

    private func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        if isLoaded { trySave() }
    }

    private func trySave() {
        let config = LLMConfig(baseURL: baseURL, model: model)
        try? configStore.saveLLMConfig(config, apiKey: apiKey)
    }
}
