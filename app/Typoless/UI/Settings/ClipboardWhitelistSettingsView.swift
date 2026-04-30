import SwiftUI

struct ClipboardWhitelistSettingsView: View {
    let configStore: ConfigStore

    @State private var pasteboardInjectionBundleIDs: [String] = []
    @State private var newBundleID: String = ""
    @State private var isLoaded = false

    var body: some View {
        Section {
            SettingsFormRow(title: "添加规则") {
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
                CompactSettingsFormRow(title: "手动规则") {
                    Text("暂无")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(Array(pasteboardInjectionBundleIDs.enumerated()), id: \.element) { index, bundleID in
                    CompactSettingsFormRow(title: index == 0 ? "手动规则" : "") {
                        HStack(spacing: 12) {
                            Text(bundleID)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("移除") {
                                removeBundleID(bundleID)
                            }
                            .fixedSize()
                        }
                    }
                }
            }

            ForEach(Array(GeneralConfig.defaultPasteboardInjectionBundleIDs.enumerated()), id: \.element) { index, bundleID in
                BuiltInWhitelistRow(
                    title: index == 0 ? "内置规则" : "",
                    bundleID: bundleID
                )
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
}

private struct BuiltInWhitelistRow: View {
    let title: String
    let bundleID: String

    var body: some View {
        CompactSettingsFormRow(title: title) {
            Text(bundleID)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct CompactSettingsFormRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        let labelWidth: CGFloat = 104
        let rowSpacing: CGFloat = 12

        return HStack(alignment: .center, spacing: rowSpacing) {
            Text(title)
                .frame(width: labelWidth, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
