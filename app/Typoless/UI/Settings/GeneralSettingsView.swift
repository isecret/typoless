import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    private enum Layout {
        static let translationPickerWidth: CGFloat = 160
    }

    let configStore: ConfigStore
    let updateService: AppUpdateService
    var onHotkeyCommit: ((HotkeyCombo) -> String?)?
    var onHotkeyRecordingChanged: ((Bool) -> Void)?
    var onInteractionSoundChanged: ((Bool) -> Void)?

    @State private var hotkey: HotkeyCombo = .default
    @State private var interactionSoundEnabled = true
    @State private var translationTargetLanguage: TranslationTargetLanguage = .english
    @State private var launchAtLogin = false
    @State private var isLoaded = false
    @State private var recordingPhase: HotkeyRecordingPhase = .idle
    @State private var hotkeyError: String?

    private var hotkeyIncludesFunction: Bool {
        hotkey.specialModifiers.contains { $0.key == .function }
    }

    var body: some View {
        Group {
            SettingsPaneSection {
                SettingsFormRow(title: "全局快捷键") {
                    VStack(alignment: .leading, spacing: 4) {
                        HotkeyRecorderView(
                            hotkey: hotkey,
                            onCommit: commitHotkey,
                            onPhaseChanged: { recordingPhase = $0 },
                            onRecordingStateChanged: { isRecording in
                                if isRecording {
                                    hotkeyError = nil
                                }
                                onHotkeyRecordingChanged?(isRecording)
                            }
                        )

                        if let hotkeyError {
                            Text(hotkeyError)
                                .font(.caption)
                                .foregroundStyle(Color.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(hotkeyFooterText)
                    if let conflict = HotkeySystemConflict.warning(for: hotkey), recordingPhase == .idle {
                        Text(conflict)
                    }
                    if hotkeyIncludesFunction, recordingPhase == .idle {
                        Text("已使用 Fn 键：若系统的“按下 🌐 键时”设置了切换输入法、显示表情等动作，请改为“无操作”，否则会同时触发系统动作。")
                        Button("打开键盘设置…") {
                            openKeyboardSettings()
                        }
                        .buttonStyle(.link)
                        .controlSize(.small)
                    }
                }
            }

            SettingsPaneSection {
                SettingsFormRow(title: "交互音效") {
                    Toggle("启用", isOn: $interactionSoundEnabled)
                        .labelsHidden()
                }
            } footer: {
                Text("开始和结束录音时播放提示音。")
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
                Text("录音时按 Shift+Tab 可切换到翻译模式，译文将使用这里选择的语言。")
            }

            SettingsPaneSection {
                SettingsFormRow(title: "开机自启动") {
                    Toggle("在登录时启动", isOn: $launchAtLogin)
                        .labelsHidden()
                }
            } footer: {
                Text("登录 macOS 后自动启动。")
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
        .onChange(of: interactionSoundEnabled) { immediateSaveInteractionSound() }
        .onChange(of: translationTargetLanguage) { immediateSaveGeneralConfig() }
        .onChange(of: launchAtLogin) { immediateSaveGeneralConfig() }
    }

    private var hotkeyFooterText: String {
        switch recordingPhase {
        case .idle:
            "按一次开始录音，再按一次结束。"
        case .waiting:
            "Esc 取消并保留原快捷键。"
        case .previewingModifiers:
            "松开即可保存。"
        }
    }

    @discardableResult
    private func commitHotkey(_ combo: HotkeyCombo) -> Bool {
        if let errorMessage = onHotkeyCommit?(combo) {
            hotkeyError = errorMessage
            return false
        }
        hotkey = combo
        hotkeyError = nil
        return true
    }

    private func openKeyboardSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.keyboard",
        ]
        for urlString in urls {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private func loadDraft() {
        hotkey = configStore.generalConfig.hotkey
        interactionSoundEnabled = configStore.generalConfig.interactionSoundEnabled
        translationTargetLanguage = configStore.generalConfig.translationTargetLanguage
        launchAtLogin = configStore.generalConfig.launchAtLogin
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
