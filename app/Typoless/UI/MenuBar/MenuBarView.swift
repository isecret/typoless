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
            Text(error.userMessage)
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
}
