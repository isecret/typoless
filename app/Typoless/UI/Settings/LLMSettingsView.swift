import SwiftUI

struct LLMSettingsView: View {
    let configStore: ConfigStore

    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var model: String = ""
    @State private var saveMessage: String?
    @State private var isError: Bool = false

    var body: some View {
        Form {
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

            Section {
                HStack {
                    Spacer()
                    Button("保存") {
                        save()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                }

                if let message = saveMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(isError ? .red : .green)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadDraft() }
    }

    private func loadDraft() {
        configStore.loadLLMSecretIfNeeded()
        baseURL = configStore.llmConfig.baseURL
        apiKey = configStore.openAIAPIKey
        model = configStore.llmConfig.model
    }

    private func save() {
        saveMessage = nil
        do {
            let config = LLMConfig(baseURL: baseURL, model: model)
            try configStore.saveLLMConfig(config, apiKey: apiKey)
            saveMessage = "已保存"
            isError = false
        } catch {
            saveMessage = error.localizedDescription
            isError = true
        }
    }
}
