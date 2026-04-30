import SwiftUI

struct ClipboardWhitelistSettingsView: View {
    let configStore: ConfigStore

    @State private var pasteboardInjectionBundleIDs: [String] = []
    @State private var newBundleID: String = ""
    @State private var isLoaded = false

    var body: some View {
        Section {
            settingsRow("添加规则") {
                HStack(spacing: 8) {
                    SettingsTextInputField(
                        text: $newBundleID,
                        width: 220,
                        placeholder: "Bundle ID 或前缀"
                    )

                    Button("添加") {
                        addBundleID()
                    }
                    .fixedSize()
                    .disabled(newBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if pasteboardInjectionBundleIDs.isEmpty {
                settingsRow("手动规则") {
                    Text("暂无")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(pasteboardInjectionBundleIDs, id: \.self) { bundleID in
                    HStack {
                        Text(bundleID)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("移除") {
                            removeBundleID(bundleID)
                        }
                    }
                }
            }

            ForEach(GeneralConfig.defaultPasteboardInjectionBundleIDs, id: \.self) { bundleID in
                BuiltInWhitelistRow(bundleID: bundleID)
            }
        } header: {
            Text("剪贴板白名单")
        } footer: {
            Text("这些应用会优先使用“临时写入剪贴板并粘贴，再恢复原剪贴板”的注入策略，适合终端、Electron 和部分 IDE。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            loadDraft()
            isLoaded = true
        }
        .onChange(of: pasteboardInjectionBundleIDs) { immediateSave() }
    }

    private func loadDraft() {
        pasteboardInjectionBundleIDs = configStore.generalConfig.pasteboardInjectionBundleIDs.sorted()
    }

    private func immediateSave() {
        guard isLoaded else { return }
        let config = GeneralConfig(
            hotkey: configStore.generalConfig.hotkey,
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

    @ViewBuilder
    private func settingsRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
            Spacer(minLength: 16)
            content()
        }
    }
}

private struct BuiltInWhitelistRow: View {
    let bundleID: String

    var body: some View {
        LabeledContent("内置规则") {
            Text(bundleID)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
        }
    }
}
