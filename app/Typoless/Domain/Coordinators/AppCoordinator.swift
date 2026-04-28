import AppKit
import Foundation
import SwiftUI

/// 应用生命周期协调器，负责菜单栏入口、设置页与快捷键管理
@MainActor
@Observable
final class AppCoordinator {
    let configStore: ConfigStore
    let permissionsManager: PermissionsManager
    let sessionCoordinator: SessionCoordinator
    let recentRecordStore: RecentRecordStore
    let hotkeyManager: HotkeyManager

    private let textInjector = TextInjector()
    private var settingsWindowController: NSWindowController?

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

    /// 通过 AppKit 托管单例设置窗口，避免依赖 SwiftUI 默认 selector
    func openSettingsWindow() {
        if settingsWindowController == nil {
            let hostingController = NSHostingController(rootView: SettingsView(appCoordinator: self))
            let window = NSWindow(contentViewController: hostingController)
            window.title = "设置"
            window.setContentSize(NSSize(width: 520, height: 600))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindowController = NSWindowController(window: window)
        }

        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 清空最近记录
    func clearHistory() {
        recentRecordStore.clearAll()
    }

    /// 重新注入文本到当前焦点应用
    func reinjectText(_ text: String) {
        let selfBundleID = Bundle.main.bundleIdentifier ?? "com.isecret.typoless"

        Task { @MainActor in
            // 等待菜单关闭后焦点回到前一个应用，轮询排除自身
            var targetPID: pid_t?
            var targetBundleID: String?

            let retryIntervals: [Duration] = [.milliseconds(50), .milliseconds(100), .milliseconds(150), .milliseconds(200), .milliseconds(300)]
            for interval in retryIntervals {
                try? await Task.sleep(for: interval)

                if let app = NSWorkspace.shared.frontmostApplication,
                   app.bundleIdentifier != selfBundleID {
                    targetPID = app.processIdentifier
                    targetBundleID = app.bundleIdentifier
                    break
                }
            }

            // 超时后仍为自身，使用当前前台应用（最后兜底）
            if targetPID == nil {
                let app = NSWorkspace.shared.frontmostApplication
                targetPID = app?.processIdentifier
                targetBundleID = app?.bundleIdentifier
            }

            try? textInjector.inject(
                text: text,
                targetPID: targetPID,
                targetBundleID: targetBundleID,
                pasteboardPreferredBundleIDs: configStore.generalConfig.effectivePasteboardInjectionBundleIDs
            )
        }
    }

    // MARK: - 快捷键

    /// 注册全局快捷键并绑定按下切换回调
    func setupHotkey() {
        let hotkey = configStore.generalConfig.hotkey
        hotkeyManager.register(hotkey: hotkey)

        hotkeyManager.onKeyDown = { [weak self] in
            guard let self else { return }
            switch self.sessionCoordinator.state {
            case .idle:
                self.sessionCoordinator.startRecording()
            case .recording:
                self.sessionCoordinator.finishRecording()
            default:
                break
            }
        }
        hotkeyManager.onKeyUp = nil
    }
}
