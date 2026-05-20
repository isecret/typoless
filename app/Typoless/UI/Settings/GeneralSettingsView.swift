import SwiftUI

struct GeneralSettingsView: View {
    let configStore: ConfigStore
    var onHotkeyChanged: (() -> Void)?

    @State private var hotkey: HotkeyCombo = .default
    @State private var interactionSoundEnabled = true
    @State private var translationTargetLanguage: TranslationTargetLanguage = .english
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

            Section {
                SettingsFormRow(title: "翻译目标语言") {
                    Picker("", selection: $translationTargetLanguage) {
                        ForEach(TranslationTargetLanguage.allCases, id: \.self) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            } header: {
                Text("翻译")
            } footer: {
                Text("录音结束后将文本翻译为目标语言（仅在录音中切换至翻译模式时生效）")
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
        .onChange(of: translationTargetLanguage) { immediateSaveGeneralConfig() }
    }

    private func loadDraft() {
        hotkey = configStore.generalConfig.hotkey
        interactionSoundEnabled = configStore.generalConfig.interactionSoundEnabled
        translationTargetLanguage = configStore.generalConfig.translationTargetLanguage
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
            interactionSoundEnabled: interactionSoundEnabled,
            translationTargetLanguage: translationTargetLanguage
        )
        try? configStore.saveGeneralConfig(config)
    }
}
