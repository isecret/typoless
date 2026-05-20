import SwiftUI

struct LLMSettingsView: View {
    let configStore: ConfigStore

    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var model: String = ""
    @State private var validationService: LLMValidationService?
    @State private var modelListService: LLMModelListService?
    @State private var hasTriggeredValidation = false
    @State private var isLoaded = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        SettingsPaneSection {
            SettingsFormRow(title: "Base URL") {
                SettingsTextInputField(text: $baseURL)
            }
            SettingsFormRow(title: "API Key") {
                SettingsSecureInputField(text: $apiKey)
            }
            SettingsFormRow(title: "Model") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        SettingsTextInputField(text: $model, width: 276)

                        Menu {
                            modelListMenuContent
                        } label: {
                            Image(systemName: "chevron.down.circle")
                                .frame(width: 18, height: 18)
                        }
                        .disabled(modelListService?.models.isEmpty ?? true)
                        .buttonStyle(.borderless)
                        .help("选择模型")

                        Button {
                            loadModelList(force: true)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .frame(width: 18, height: 18)
                        }
                        .disabled(!currentModelListInput().isComplete || modelListService?.status == .loading)
                        .buttonStyle(.borderless)
                        .help("刷新模型列表")
                    }

                    modelListStatusView
                }
            }
            SettingsFormRow(title: "模型状态") {
                VStack(alignment: .leading, spacing: 4) {
                    validationStatusView

                    if hasTriggeredValidation,
                       let errorMessage = validationService?.lastErrorMessage,
                       validationService?.status == .failed {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                            .frame(width: SettingsFormLayout.controlWidth, alignment: .leading)
                    }
                }
            }
        } footer: {
            Text("支持 OpenAI Chat Completions 兼容接口。填写后自动启用 AI 润色。")
        }
        .onAppear {
            loadDraft()
            _ = ensureValidationService()
            _ = ensureModelListService()
            isLoaded = true
            loadModelList()
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
        hasTriggeredValidation = false
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
        hasTriggeredValidation = true

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

        loadModelList()
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

    private func ensureModelListService() -> LLMModelListService {
        if let modelListService {
            return modelListService
        }

        let service = LLMModelListService()
        modelListService = service
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

    private func currentModelListInput() -> LLMModelListInput {
        LLMModelListInput(
            baseURL: baseURL,
            apiKey: apiKey
        )
    }

    private func loadModelList(force: Bool = false) {
        ensureModelListService().load(currentModelListInput(), force: force)
    }

    @ViewBuilder
    private var modelListMenuContent: some View {
        ForEach(modelListService?.models ?? [], id: \.self) { modelName in
            Button(modelName) {
                model = modelName
            }
        }
    }

    @ViewBuilder
    private var modelListStatusView: some View {
        switch modelListService?.status ?? .incomplete {
        case .incomplete:
            EmptyView()
        case .loading:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("正在获取模型列表")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case .loaded:
            Text("已获取 \(modelListService?.models.count ?? 0) 个模型，也可手动输入")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .unavailable:
            Text("无法获取模型列表，可手动输入")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var validationStatusView: some View {
        if !hasTriggeredValidation {
            statusIndicator(
                text: currentValidationInput().isComplete ? "已就绪" : "未就绪",
                systemImage: currentValidationInput().isComplete ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                color: currentValidationInput().isComplete ? .green : .orange
            )
        } else {
            switch validationService?.status ?? .incomplete {
            case .incomplete:
                statusIndicator(
                    text: "未就绪",
                    systemImage: "exclamationmark.triangle.fill",
                    color: .orange
                )
            case .checking, .ready:
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
