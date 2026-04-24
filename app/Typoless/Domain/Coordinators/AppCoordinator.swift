import AppKit
import Foundation

/// 应用生命周期协调器，负责菜单栏入口、设置页与快捷键管理
@MainActor
@Observable
final class AppCoordinator {
    let configStore: ConfigStore
    let permissionsManager: PermissionsManager
    let sessionCoordinator: SessionCoordinator
    let hotkeyManager: HotkeyManager

    init() {
        let store = ConfigStore()
        let perms = PermissionsManager()
        configStore = store
        permissionsManager = perms
        sessionCoordinator = SessionCoordinator(permissionsManager: perms, configStore: store)
        hotkeyManager = HotkeyManager()
    }

    /// 应用启动后注册快捷键并检查首次配置
    func handleAppLaunch() {
        setupHotkey()

        guard !configStore.hasCompletedInitialSetup else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            openSettingsWindow()
        }
    }

    /// 通过 AppKit 打开设置窗口
    func openSettingsWindow() {
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

    // MARK: - 快捷键

    /// 注册全局快捷键并绑定录音回调
    func setupHotkey() {
        let hotkey = configStore.generalConfig.hotkey
        hotkeyManager.register(hotkey: hotkey)

        hotkeyManager.onKeyDown = { [weak self] in
            self?.sessionCoordinator.startRecording()
        }
        hotkeyManager.onKeyUp = { [weak self] in
            self?.sessionCoordinator.finishRecording()
        }
    }
}
