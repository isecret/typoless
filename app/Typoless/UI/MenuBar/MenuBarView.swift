import SwiftUI

struct MenuBarView: View {
    let appCoordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow

    private var state: SessionState {
        appCoordinator.sessionCoordinator.state
    }

    private var lastInjectionFailureText: String? {
        appCoordinator.sessionCoordinator.lastInjectionFailureText
    }

    var body: some View {
        if let error = appCoordinator.sessionCoordinator.currentError {
            Label(error.userMessage, systemImage: "exclamationmark.triangle.fill")
                .imageScale(.small)
                .foregroundStyle(.secondary)

            Divider()
        }

        if let failureText = lastInjectionFailureText {
            let preview = failureText.count > 20
                ? String(failureText.prefix(20)) + "…"
                : failureText
            Button(preview) {
                appCoordinator.copyLastFailureTextToClipboard()
            }

            Divider()
        }

        if state.isCancellable {
            Button("取消当前任务") {
                appCoordinator.sessionCoordinator.cancel()
            }
            Divider()
        }

        microphonePicker

        Divider()

        Button("设置") {
            appCoordinator.openSettingsWindow()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("关于 Typoless") {
            openWindow(id: "about")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("退出") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private var microphonePicker: some View {
        Picker("麦克风", selection: Binding(
            get: {
                appCoordinator.audioDeviceManager.menuSelectionID
            },
            set: { id in
                appCoordinator.audioDeviceManager.selectMenuItem(id: id)
            }
        )) {
            if appCoordinator.audioDeviceManager.selectedDeviceID != nil,
               !appCoordinator.audioDeviceManager.selectedDeviceIsAvailable {
                Text("已选设备不可用，当前跟随系统默认")
                    .tag(AudioDeviceManager.unavailableSelectionID)
                    .disabled(true)
            }

            Text("跟随系统默认")
                .tag(AudioDeviceManager.systemDefaultSelectionID)

            ForEach(appCoordinator.audioDeviceManager.devices) { device in
                Text(device.name)
                    .tag(device.id)
            }
        }
        .disabled(state.isProcessing)
        .onAppear {
            appCoordinator.audioDeviceManager.refreshDevices()
        }
    }
}
