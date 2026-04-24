import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            PlaceholderTab(title: "ASR 配置", icon: "waveform", description: "腾讯云 ASR 配置将在 E2 中实现")
            PlaceholderTab(title: "LLM 配置", icon: "brain", description: "OpenAI 兼容 LLM 配置将在 E2 中实现")
            PlaceholderTab(title: "快捷键", icon: "keyboard", description: "全局快捷键配置将在 E2 中实现")
            PlaceholderTab(title: "权限", icon: "lock.shield", description: "权限检测与引导将在 E3 中实现")
            PlaceholderTab(title: "诊断", icon: "stethoscope", description: "诊断信息将在 E9 中实现")
            PlaceholderTab(title: "最近记录", icon: "clock", description: "最近记录将在 E9 中实现")
        }
        .frame(width: 520, height: 360)
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
