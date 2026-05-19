import AppKit
import Foundation
import SwiftUI

/// 应用生命周期协调器，负责菜单栏入口、设置页与快捷键管理
@MainActor
@Observable
final class AppCoordinator {
    enum HotkeyAction: Equatable {
        case startRecording
        case finishRecording
    }

    let configStore: ConfigStore
    let permissionsManager: PermissionsManager
    let audioDeviceManager: AudioDeviceManager
    let sessionCoordinator: SessionCoordinator
    let hotkeyManager: HotkeyManager
    let hudFeedbackController: HUDFeedbackController
    let dictionaryStore: PersonalDictionaryStore
    let updateService: AppUpdateService

    private var settingsWindowController: NSWindowController?

    init() {
        let store = ConfigStore()
        let perms = PermissionsManager()
        let audioDevices = AudioDeviceManager(configStore: store)
        let dict = PersonalDictionaryStore()
        configStore = store
        permissionsManager = perms
        audioDeviceManager = audioDevices
        dictionaryStore = dict
        sessionCoordinator = SessionCoordinator(
            permissionsManager: perms,
            configStore: store,
            audioDeviceManager: audioDevices,
            dictionaryStore: dict
        )
        hotkeyManager = HotkeyManager()
        updateService = AppUpdateService(configStore: store)

        let hud = HUDFeedbackController()
        hudFeedbackController = hud
        sessionCoordinator.onFeedbackEvent = { [weak hud] event in
            hud?.handleEvent(event)
        }
        hud.isInteractionSoundEnabled = { [weak store] in
            store?.generalConfig.interactionSoundEnabled ?? true
        }
        hud.audioLevelProvider = { [weak sessionCoordinator] in
            sessionCoordinator?.currentAudioLevel() ?? 0
        }
        hud.onCancelRecording = { [weak sessionCoordinator] in
            sessionCoordinator?.cancel()
        }
        hud.onConfirmRecording = { [weak sessionCoordinator] in
            sessionCoordinator?.finishRecording()
        }
    }

    /// 应用启动后注册快捷键并检查首次配置
    func handleAppLaunch() {
        setupHotkey()
        updateService.start()

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
            window.initialFirstResponder = window.contentView
            settingsWindowController = NSWindowController(window: window)
        }

        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        if let window = settingsWindowController?.window {
            DispatchQueue.main.async {
                window.makeFirstResponder(window.contentView)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 将最近一次注入失败文本复制到系统剪贴板
    func copyLastFailureTextToClipboard() {
        guard let text = sessionCoordinator.lastInjectionFailureText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - 快捷键

    /// 注册全局快捷键并绑定按下切换回调
    func setupHotkey() {
        let hotkey = configStore.generalConfig.hotkey
        hotkeyManager.register(hotkey: hotkey)

        hotkeyManager.onKeyDown = { [weak self] in
            self?.handleHotkeyEvent()
        }
        hotkeyManager.onKeyUp = nil
    }

    static func hotkeyAction(for sessionState: SessionState) -> HotkeyAction? {
        switch sessionState {
        case let state where state.allowsRecordingStart:
            .startRecording
        case .recording:
            .finishRecording
        default:
            nil
        }
    }

    private func handleHotkeyEvent() {
        guard let action = Self.hotkeyAction(for: sessionCoordinator.state) else {
            return
        }

        switch action {
        case .startRecording:
            sessionCoordinator.startRecording()
        case .finishRecording:
            sessionCoordinator.finishRecording()
        }
    }
}
