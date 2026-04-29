import SwiftUI

struct GeneralSettingsView: View {
    let configStore: ConfigStore
    var onHotkeyChanged: (() -> Void)?

    @State private var hotkey: HotkeyCombo = .default
    @State private var isLoaded = false

    var body: some View {
        Section {
            HStack {
                Text("全局快捷键")
                Spacer()
                HotkeyRecorderView(hotkey: $hotkey)
            }
        } header: {
            Text("全局快捷键")
        } footer: {
            Text("触发录音的全局快捷键")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            loadDraft()
            isLoaded = true
        }
        .onChange(of: hotkey) { immediateSaveWithHotkey() }
    }

    private func loadDraft() {
        hotkey = configStore.generalConfig.hotkey
    }

    private func immediateSaveWithHotkey() {
        guard isLoaded else { return }
        let config = GeneralConfig(
            hotkey: hotkey,
            pasteboardInjectionBundleIDs: configStore.generalConfig.pasteboardInjectionBundleIDs.sorted()
        )
        try? configStore.saveGeneralConfig(config)
        onHotkeyChanged?()
    }
}
