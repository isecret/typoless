import SwiftUI

struct GeneralSettingsView: View {
    let configStore: ConfigStore
    let updateService: AppUpdateService
    var onHotkeyChanged: (() -> Void)?

    @State private var hotkey: HotkeyCombo = .default
    @State private var interactionSoundEnabled = true
    @State private var translationTargetLanguage: TranslationTargetLanguage = .english
    @State private var isLoaded = false

    var body: some View {
        Group {
            SettingsPaneSection {
                SettingsFormRow(title: "全局快捷键") {
                    HotkeyRecorderView(hotkey: $hotkey)
                }
            } footer: {
                Text("触发录音的全局快捷键")
            }

            SettingsPaneSection {
                SettingsFormRow(title: "交互音效") {
                    Toggle("启用", isOn: $interactionSoundEnabled)
                        .labelsHidden()
                }
            } footer: {
                Text("开始录音和结束录音时播放提示音")
            }

            SettingsPaneSection {
                SettingsFormRow(title: "翻译目标语言") {
                    Picker("", selection: $translationTargetLanguage) {
                        ForEach(TranslationTargetLanguage.allCases, id: \.self) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            } footer: {
                Text("按下 Shift+Tab 切换至翻译模式将文本翻译为目标语言")
            }

            SettingsPaneSection {
                SettingsFormRow(title: "自动检查更新") {
                    HStack(spacing: 14) {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { updateService.automaticallyChecksForUpdates },
                                set: { updateService.setAutomaticallyChecksForUpdates($0) }
                            )
                        )
                        .toggleStyle(.checkbox)
                        .labelsHidden()

                        Button("检查更新") {
                            updateService.checkForUpdates()
                        }
                        .disabled(!updateService.canCheckForUpdates)
                    }
                }
            } footer: {
                Text("当前版本：v\(appVersion)")
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

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}
