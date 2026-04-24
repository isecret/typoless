import AppKit
import Foundation

/// 应用生命周期协调器，负责菜单栏入口与设置页管理
@MainActor
@Observable
final class AppCoordinator {
    let sessionCoordinator = SessionCoordinator()
    let configStore = ConfigStore()

    /// 应用启动后检查是否需要自动打开设置页
    func handleAppLaunch() {
        guard !configStore.hasCompletedInitialSetup else { return }
        // 延迟一帧确保窗口系统就绪
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            openSettingsWindow()
        }
    }

    /// 通过 AppKit 打开设置窗口
    func openSettingsWindow() {
        // macOS 14+ 使用 SettingsLink / showSettingsWindow
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 清空最近记录（E9 实现）
    func clearHistory() {
        // Placeholder — will be implemented in E9
    }
}
