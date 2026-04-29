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
            LabeledContent("Base URL") {
                TextField("", text: $baseURL)
                    .settingsInputFieldStyle()
            }
            LabeledContent("API Key") {
                SecureField("", text: $apiKey)
                    .settingsInputFieldStyle()
            }
            LabeledContent("Model") {
                TextField("", text: $model)
                    .settingsInputFieldStyle()
            }
        } header: {
            Text("AI 配置")
        } footer: {
            Text("支持任何兼容 OpenAI Chat Completions 的接口。填写 Base URL、API Key、Model 后会自动启用 AI 润色。")
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

private extension View {
    func settingsInputFieldStyle() -> some View {
        frame(width: 320)
            .lineLimit(1)
            .truncationMode(.tail)
            .textFieldStyle(.roundedBorder)
            .controlSize(.regular)
            .frame(height: 28)
    }
}
