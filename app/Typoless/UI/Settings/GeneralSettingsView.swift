import SwiftUI

struct GeneralSettingsView: View {
    let configStore: ConfigStore
    var onHotkeyChanged: (() -> Void)?

    @State private var enableAIPolish: Bool = true
    @State private var hotkey: HotkeyCombo = .default
    @State private var isRecordingHotkey: Bool = false
    @State private var pasteboardInjectionBundleIDs: [String] = []
    @State private var newBundleID: String = ""
    @State private var isLoaded = false

    var body: some View {
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
                TextField("Bundle ID 或前缀（如 com.jetbrains.*）", text: $newBundleID)
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
                            removeBundleID(bundleID)
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
        .onAppear {
            loadDraft()
            isLoaded = true
        }
        .onChange(of: enableAIPolish) { immediateSave() }
        .onChange(of: hotkey) { immediateSaveWithHotkey() }
        .onChange(of: pasteboardInjectionBundleIDs) { immediateSave() }
    }

    private func loadDraft() {
        enableAIPolish = configStore.generalConfig.enableAIPolish
        hotkey = configStore.generalConfig.hotkey
        pasteboardInjectionBundleIDs = configStore.generalConfig.pasteboardInjectionBundleIDs.sorted()
    }

    private func immediateSave() {
        guard isLoaded else { return }
        trySave()
    }

    private func immediateSaveWithHotkey() {
        guard isLoaded else { return }
        trySave()
        onHotkeyChanged?()
    }

    private func trySave() {
        let config = GeneralConfig(
            hotkey: hotkey,
            enableAIPolish: enableAIPolish,
            pasteboardInjectionBundleIDs: pasteboardInjectionBundleIDs.sorted()
        )
        try? configStore.saveGeneralConfig(config)
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

    private func removeBundleID(_ bundleID: String) {
        pasteboardInjectionBundleIDs.removeAll { $0 == bundleID }
    }
}
