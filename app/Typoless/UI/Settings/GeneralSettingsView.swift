import SwiftUI

struct GeneralSettingsView: View {
    let configStore: ConfigStore
    var onHotkeyChanged: (() -> Void)?

    @State private var hotkey: HotkeyCombo = .default
    @State private var interactionSoundEnabled = true
    @State private var isLoaded = false

    var body: some View {
        Group {
            Section {
                SettingsFormRow(title: "全局快捷键") {
                    HotkeyRecorderView(hotkey: $hotkey)
                }
            } header: {
                Text("全局快捷键")
            } footer: {
                Text("触发录音的全局快捷键")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                SettingsFormRow(title: "交互音效") {
                    Toggle("启用", isOn: $interactionSoundEnabled)
                        .labelsHidden()
                }
            } header: {
                Text("反馈")
            } footer: {
                Text("开始录音和结束录音时播放提示音")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            loadDraft()
            isLoaded = true
        }
        .onChange(of: hotkey) { immediateSaveWithHotkey() }
        .onChange(of: interactionSoundEnabled) { immediateSaveGeneralConfig() }
    }

    private func loadDraft() {
        hotkey = configStore.generalConfig.hotkey
        interactionSoundEnabled = configStore.generalConfig.interactionSoundEnabled
    }

    private func immediateSaveWithHotkey() {
        guard isLoaded else { return }
        immediateSaveGeneralConfig()
        onHotkeyChanged?()
    }

    private func immediateSaveGeneralConfig() {
        guard isLoaded else { return }
        let config = GeneralConfig(
            hotkey: hotkey,
            interactionSoundEnabled: interactionSoundEnabled
        )
        try? configStore.saveGeneralConfig(config)
    }
}
