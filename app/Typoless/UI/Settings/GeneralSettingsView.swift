import SwiftUI

struct GeneralSettingsView: View {
    private enum Layout {
        static let translationPickerWidth: CGFloat = 160
    }

    let configStore: ConfigStore
    let updateService: AppUpdateService
    var onHotkeyChanged: (() -> Void)?
    var onHotkeyRecordingChanged: ((Bool) -> Void)?
    var onInteractionSoundChanged: ((Bool) -> Void)?

    @State private var hotkey: HotkeyCombo = .default
    @State private var interactionSoundEnabled = true
    @State private var translationTargetLanguage: TranslationTargetLanguage = .english
    @State private var launchAtLogin = false
    @State private var isLoaded = false

    var body: some View {
        Group {
            SettingsPaneSection {
                SettingsFormRow(title: "全局快捷键") {
                    HotkeyRecorderView(
                        hotkey: $hotkey,
                        onRecordingStateChanged: { isRecording in
                            onHotkeyRecordingChanged?(isRecording)
                        }
                    )
                    .fixedSize(horizontal: true, vertical: false)
                }
            } footer: {
                Text("支持纯修饰键；按下后松开即可完成录制。")
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
                    HStack(spacing: 0) {
                        Picker("", selection: $translationTargetLanguage) {
                            ForEach(TranslationTargetLanguage.allCases, id: \.self) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: Layout.translationPickerWidth, alignment: .leading)

                        Spacer(minLength: 0)
                    }
                }
            } footer: {
                Text("按下 Shift+Tab 切换至翻译模式将文本翻译为目标语言")
            }

            SettingsPaneSection {
                SettingsFormRow(title: "开机自启动") {
                    Toggle("在登录时启动", isOn: $launchAtLogin)
                        .labelsHidden()
                }
            } footer: {
                Text("启用后将随 macOS 登录时自启动")
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
        .onChange(of: interactionSoundEnabled) { immediateSaveInteractionSound() }
        .onChange(of: translationTargetLanguage) { immediateSaveGeneralConfig() }
        .onChange(of: launchAtLogin) { immediateSaveGeneralConfig() }
    }

    private func loadDraft() {
        hotkey = configStore.generalConfig.hotkey
        interactionSoundEnabled = configStore.generalConfig.interactionSoundEnabled
        translationTargetLanguage = configStore.generalConfig.translationTargetLanguage
        launchAtLogin = configStore.generalConfig.launchAtLogin
    }

    private func immediateSaveWithHotkey() {
        guard isLoaded else { return }
        immediateSaveGeneralConfig()
        onHotkeyChanged?()
    }

    private func immediateSaveInteractionSound() {
        guard isLoaded else { return }
        immediateSaveGeneralConfig()
        onInteractionSoundChanged?(interactionSoundEnabled)
    }

    private func immediateSaveGeneralConfig() {
        guard isLoaded else { return }
        // Apply launch-at-login change first so system state matches user preference
        try? LaunchAtLoginManager.setEnabled(launchAtLogin)

        let config = GeneralConfig(
            hotkey: hotkey,
            interactionSoundEnabled: interactionSoundEnabled,
            translationTargetLanguage: translationTargetLanguage,
            launchAtLogin: launchAtLogin
        )
        try? configStore.saveGeneralConfig(config)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}
