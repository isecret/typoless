import SwiftUI

struct LLMSettingsView: View {
    let configStore: ConfigStore

    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var model: String = ""
    @State private var validationService: LLMValidationService?
    @State private var isLoaded = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        Section {
            SettingsFormRow(title: "Base URL") {
                SettingsTextInputField(text: $baseURL)
            }
            SettingsFormRow(title: "API Key") {
                SettingsSecureInputField(text: $apiKey)
            }
            SettingsFormRow(title: "Model") {
                SettingsTextInputField(text: $model, width: 220)
            }
            SettingsFormRow(title: "模型状态") {
                VStack(alignment: .trailing, spacing: 4) {
                    validationStatusView

                    if let errorMessage = validationService?.lastErrorMessage,
                       validationService?.status == .failed {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                            .frame(width: 320, alignment: .trailing)
                    }
                }
            }
        } header: {
            Text("AI 配置")
        } footer: {
            Text("支持 OpenAI Chat Completions 兼容接口。填写后自动启用 AI 润色。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            loadDraft()
            _ = ensureValidationService()
            isLoaded = true
            validationService?.validate(currentValidationInput(), force: true)
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
            trySaveAndValidate()
        }
    }

    private func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        if isLoaded { trySaveAndValidate() }
    }

    private func trySaveAndValidate() {
        let validationService = ensureValidationService()
        let config = LLMConfig(baseURL: baseURL, model: model)

        do {
            try configStore.saveLLMConfig(config, apiKey: apiKey)
            validationService.validate(currentValidationInput())
        } catch {
            validationService.validate(
                LLMValidationInput(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    model: model,
                    thinkingDisabled: false
                )
            )
        }
    }

    private func ensureValidationService() -> LLMValidationService {
        if let validationService {
            return validationService
        }

        let service = LLMValidationService(onThinkingUnsupported: {
            try? configStore.markThinkingDisabledForCurrentLLM()
        })
        validationService = service
        return service
    }

    private func currentValidationInput() -> LLMValidationInput {
        LLMValidationInput(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            thinkingDisabled: configStore.llmConfig.thinkingDisabled
        )
    }

    @ViewBuilder
    private var validationStatusView: some View {
        switch validationService?.status ?? .incomplete {
        case .incomplete:
            statusIndicator(
                text: "配置未完成",
                systemImage: "exclamationmark.triangle.fill",
                color: .orange
            )
        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("检查中")
            }
            .foregroundStyle(.secondary)
        case .ready:
            statusIndicator(
                text: "已就绪",
                systemImage: "checkmark.circle.fill",
                color: .green
            )
        case .failed:
            statusIndicator(
                text: "未就绪",
                systemImage: "xmark.circle.fill",
                color: .red
            )
        }
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
