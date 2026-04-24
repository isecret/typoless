import SwiftUI

struct SettingsView: View {
    @Bindable var appCoordinator: AppCoordinator

    var body: some View {
        TabView(selection: $appCoordinator.selectedSettingsTab) {
            ASRSettingsView(configStore: appCoordinator.configStore)
                .tabItem { Label("ASR 配置", systemImage: "waveform") }
                .tag(SettingsTab.asr)
            LLMSettingsView(configStore: appCoordinator.configStore)
                .tabItem { Label("LLM 配置", systemImage: "brain") }
                .tag(SettingsTab.llm)
            GeneralSettingsView(configStore: appCoordinator.configStore, onHotkeyChanged: {
                appCoordinator.setupHotkey()
            })
                .tabItem { Label("通用", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            PermissionsSettingsView(permissionsManager: appCoordinator.permissionsManager)
                .tabItem { Label("权限", systemImage: "lock.shield") }
                .tag(SettingsTab.permissions)
            DiagnosticsView(sessionCoordinator: appCoordinator.sessionCoordinator)
                .tabItem { Label("诊断", systemImage: "stethoscope") }
                .tag(SettingsTab.diagnostics)
            RecentRecordsView(recentRecordStore: appCoordinator.recentRecordStore)
                .tabItem { Label("最近记录", systemImage: "clock") }
                .tag(SettingsTab.recentRecords)
        }
        .frame(width: 520, height: 400)
    }
}
