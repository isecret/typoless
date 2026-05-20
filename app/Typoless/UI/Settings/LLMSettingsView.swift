import AppKit
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
                        SettingsTextInputField(text: $model, width: 334)
                        modelListPickerButton
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
            Text("支持 OpenAI Chat Completions 兼容接口。配置完整后，在识别后自动整理文本。")
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

    private var hasModelList: Bool {
        !(modelListService?.models.isEmpty ?? true)
    }

    @ViewBuilder
    private var modelListPickerButton: some View {
        ModelListPickerButton(
            models: modelListService?.models ?? [],
            help: "选择模型",
            onSelect: { model = $0 }
        )
        .frame(width: 18, height: 18)
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
            EmptyView()
        case .unavailable:
            EmptyView()
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

private struct ModelListPickerButton: NSViewRepresentable {
    let models: [String]
    let help: String
    let onSelect: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(models: models, onSelect: onSelect)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
        button.bezelStyle = .inline
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.image = Self.chevronImage()
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        button.setButtonType(.momentaryChange)
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.models = models
        context.coordinator.onSelect = onSelect
        nsView.isEnabled = true
        nsView.toolTip = help
        nsView.contentTintColor = .secondaryLabelColor
    }

    private static func chevronImage() -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        return NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "选择模型")?
            .withSymbolConfiguration(configuration)
    }

    final class Coordinator: NSObject {
        var models: [String]
        var onSelect: (String) -> Void

        init(models: [String], onSelect: @escaping (String) -> Void) {
            self.models = models
            self.onSelect = onSelect
        }

        @MainActor
        @objc func showMenu(_ sender: NSButton) {
            let menu = NSMenu()

            if models.isEmpty {
                let item = NSMenuItem(title: "暂未获取到模型列表", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            } else {
                for model in models {
                    let item = NSMenuItem(title: model, action: #selector(selectModel(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = model
                    menu.addItem(item)
                }
            }

            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
        }

        @MainActor
        @objc private func selectModel(_ sender: NSMenuItem) {
            guard let model = sender.representedObject as? String else { return }
            onSelect(model)
        }
    }
}
