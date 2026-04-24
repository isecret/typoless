import AppKit
import Foundation

/// 设置页 Tab 标识
enum SettingsTab: Int, Hashable {
    case asr
    case llm
    case general
    case permissions
    case diagnostics
    case recentRecords
}

/// 应用生命周期协调器，负责菜单栏入口、设置页与快捷键管理
@MainActor
@Observable
final class AppCoordinator {
    let configStore: ConfigStore
    let permissionsManager: PermissionsManager
    let sessionCoordinator: SessionCoordinator
    let recentRecordStore: RecentRecordStore
    let hotkeyManager: HotkeyManager

    var selectedSettingsTab: SettingsTab = .asr

    init() {
        let store = ConfigStore()
        let perms = PermissionsManager()
        let history = RecentRecordStore()
        configStore = store
        permissionsManager = perms
        recentRecordStore = history
        sessionCoordinator = SessionCoordinator(permissionsManager: perms, configStore: store, recentRecordStore: history)
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

    /// 打开设置窗口并跳转到指定 Tab
    func openSettings(tab: SettingsTab) {
        selectedSettingsTab = tab
        openSettingsWindow()
    }

    /// 清空最近记录
    func clearHistory() {
        recentRecordStore.clearAll()
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
