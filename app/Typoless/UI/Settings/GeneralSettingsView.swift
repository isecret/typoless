import SwiftUI

struct GeneralSettingsView: View {
    let configStore: ConfigStore

    @State private var enableAIPolish: Bool = true
    @State private var hotkey: HotkeyCombo = .default
    @State private var isRecordingHotkey: Bool = false
    @State private var saveMessage: String?
    @State private var isError: Bool = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("全局快捷键")
                    Spacer()
                    HotkeyRecorderView(hotkey: $hotkey, isRecording: $isRecordingHotkey)
                }
            } header: {
                Text("快捷键")
            } footer: {
                Text("用于触发按住说话的全局快捷键")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("启用 AI 润色", isOn: $enableAIPolish)
            } header: {
                Text("功能")
            } footer: {
                Text("关闭后将直接输出 ASR 识别原文")
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
        enableAIPolish = configStore.generalConfig.enableAIPolish
        hotkey = configStore.generalConfig.hotkey
    }

    private func save() {
        saveMessage = nil
        do {
            let config = GeneralConfig(hotkey: hotkey, enableAIPolish: enableAIPolish)
            try configStore.saveGeneralConfig(config)
            saveMessage = "已保存"
            isError = false
        } catch {
            saveMessage = error.localizedDescription
            isError = true
        }
    }
}
