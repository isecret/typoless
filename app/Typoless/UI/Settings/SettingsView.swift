import SwiftUI

struct SettingsView: View {
    let configStore: ConfigStore

    var body: some View {
        TabView {
            ASRSettingsView(configStore: configStore)
                .tabItem { Label("ASR 配置", systemImage: "waveform") }
            LLMSettingsView(configStore: configStore)
                .tabItem { Label("LLM 配置", systemImage: "brain") }
            GeneralSettingsView(configStore: configStore)
                .tabItem { Label("通用", systemImage: "gearshape") }
            PlaceholderTab(title: "权限", icon: "lock.shield", description: "权限检测与引导将在 E3 中实现")
            PlaceholderTab(title: "诊断", icon: "stethoscope", description: "诊断信息将在 E9 中实现")
            PlaceholderTab(title: "最近记录", icon: "clock", description: "最近记录将在 E9 中实现")
        }
        .frame(width: 520, height: 400)
    }
}

private struct PlaceholderTab: View {
    let title: String
    let icon: String
    let description: String

    var body: some View {
        VStack {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(description)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tabItem {
            Label(title, systemImage: icon)
        }
    }
}
