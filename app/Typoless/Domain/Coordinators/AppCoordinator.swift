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

    var selectedSettingsTab: SettingsTab = .general {
        didSet {
            resizeSettingsWindow(to: selectedSettingsTab, animated: true)
        }
    }

    private var settingsWindowController: NSWindowController?
    private var settingsToolbarCoordinator: SettingsToolbarCoordinator?
    private var settingsContentSizes: [SettingsTab: NSSize] = [:]

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
        hud.onToggleProcessingMode = { [weak sessionCoordinator] in
            sessionCoordinator?.toggleProcessingMode()
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
            window.title = selectedSettingsTab.title
            window.setContentSize(settingsContentSize(for: selectedSettingsTab))
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.titleVisibility = .visible
            window.toolbarStyle = .preference
            window.toolbar = makeSettingsToolbar()
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

    func updateSettingsContentSize(_ size: CGSize, for tab: SettingsTab) {
        guard size.width > 0, size.height > 0 else { return }

        let contentSize = NSSize(
            width: ceil(size.width),
            height: ceil(size.height) + 1
        )
        let previousSize = settingsContentSizes[tab]
        guard previousSize == nil
            || abs((previousSize?.width ?? 0) - contentSize.width) > 0.5
            || abs((previousSize?.height ?? 0) - contentSize.height) > 0.5
        else {
            return
        }

        settingsContentSizes[tab] = contentSize
        guard tab == selectedSettingsTab else { return }
        resizeSettingsWindow(to: tab, animated: settingsWindowController?.window?.isVisible == true)
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

    private func makeSettingsToolbar() -> NSToolbar {
        let coordinator = SettingsToolbarCoordinator { [weak self] tab in
            self?.selectedSettingsTab = tab
        }
        settingsToolbarCoordinator = coordinator

        let toolbar = NSToolbar(identifier: "TypolessSettingsToolbar")
        toolbar.delegate = coordinator
        toolbar.displayMode = .iconAndLabel
        toolbar.sizeMode = .regular
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.selectedItemIdentifier = .settingsTab(.general)
        return toolbar
    }

    private func resizeSettingsWindow(to tab: SettingsTab, animated: Bool) {
        guard let window = settingsWindowController?.window else { return }

        let currentFrame = window.frame
        window.title = tab.title

        let contentRect = NSRect(origin: .zero, size: settingsContentSize(for: tab))
        let frameSize = window.frameRect(forContentRect: contentRect).size
        let newFrame = NSRect(
            x: currentFrame.minX,
            y: currentFrame.maxY - frameSize.height,
            width: frameSize.width,
            height: frameSize.height
        )

        window.setFrame(newFrame, display: true, animate: animated)
    }

    private func settingsContentSize(for tab: SettingsTab) -> NSSize {
        settingsContentSizes[tab] ?? tab.defaultContentSize
    }
}

private final class SettingsToolbarCoordinator: NSObject, NSToolbarDelegate {
    private let onSelect: (SettingsTab) -> Void

    init(onSelect: @escaping (SettingsTab) -> Void) {
        self.onSelect = onSelect
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map { .settingsTab($0) }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let tab = itemIdentifier.settingsTab else { return nil }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.title
        item.paletteLabel = tab.title
        item.toolTip = tab.title
        item.image = NSImage(systemSymbolName: tab.systemImage, accessibilityDescription: tab.title)
        item.target = self
        item.action = #selector(selectToolbarItem(_:))
        return item
    }

    @MainActor
    @objc
    private func selectToolbarItem(_ sender: NSToolbarItem) {
        guard let tab = sender.itemIdentifier.settingsTab else { return }
        sender.toolbar?.selectedItemIdentifier = sender.itemIdentifier
        onSelect(tab)
    }
}

private extension NSToolbarItem.Identifier {
    static func settingsTab(_ tab: SettingsTab) -> NSToolbarItem.Identifier {
        NSToolbarItem.Identifier("TypolessSettingsToolbar.\(tab.rawValue)")
    }

    var settingsTab: SettingsTab? {
        let prefix = "TypolessSettingsToolbar."
        guard rawValue.hasPrefix(prefix) else { return nil }
        return SettingsTab(rawValue: String(rawValue.dropFirst(prefix.count)))
    }
}
