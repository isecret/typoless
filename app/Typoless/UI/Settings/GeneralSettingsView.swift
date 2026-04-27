import SwiftUI

struct GeneralSettingsView: View {
    let configStore: ConfigStore
    var onHotkeyChanged: (() -> Void)?

    @State private var enableAIPolish: Bool = true
    @State private var hotkey: HotkeyCombo = .default
    @State private var isRecordingHotkey: Bool = false
    @State private var pasteboardInjectionBundleIDs: [String] = []
    @State private var newBundleID: String = ""
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("内置白名单")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(GeneralConfig.defaultPasteboardInjectionBundleIDs, id: \.self) { bundleID in
                        Text(bundleID)
                            .font(.system(.body, design: .monospaced))
                    }
                }

                Divider()

                HStack {
                    TextField("手动添加 Bundle ID 或前缀（如 com.jetbrains.*）", text: $newBundleID)
                        .textFieldStyle(.roundedBorder)
                    Button("添加") {
                        addBundleID()
                    }
                    .disabled(newBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if pasteboardInjectionBundleIDs.isEmpty {
                    Text("暂无手动添加项")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pasteboardInjectionBundleIDs, id: \.self) { bundleID in
                        HStack {
                            Text(bundleID)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button("移除") {
                                pasteboardInjectionBundleIDs.removeAll { $0 == bundleID }
                            }
                        }
                    }
                }
            } header: {
                Text("剪贴板注入白名单")
            } footer: {
                Text("这些应用会优先使用“临时写入剪贴板并粘贴，再恢复原剪贴板”的注入策略，适合终端、Electron 和部分 IDE。")
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
        pasteboardInjectionBundleIDs = configStore.generalConfig.pasteboardInjectionBundleIDs.sorted()
    }

    private func save() {
        saveMessage = nil
        do {
            let config = GeneralConfig(
                hotkey: hotkey,
                enableAIPolish: enableAIPolish,
                pasteboardInjectionBundleIDs: pasteboardInjectionBundleIDs.sorted()
            )
            try configStore.saveGeneralConfig(config)
            onHotkeyChanged?()
            saveMessage = "已保存"
            isError = false
        } catch {
            saveMessage = error.localizedDescription
            isError = true
        }
    }

    private func addBundleID() {
        let trimmed = newBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !pasteboardInjectionBundleIDs.contains(trimmed) else {
            newBundleID = ""
            return
        }
        pasteboardInjectionBundleIDs.append(trimmed)
        pasteboardInjectionBundleIDs.sort()
        newBundleID = ""
    }
}
