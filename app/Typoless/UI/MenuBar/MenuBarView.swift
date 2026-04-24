import SwiftUI

struct MenuBarView: View {
    let appCoordinator: AppCoordinator
    @Environment(\.openSettings) private var openSettings

    private var state: SessionState {
        appCoordinator.sessionCoordinator.state
    }

    var body: some View {
        Text("当前状态：\(state.displayText)")

        Divider()

        if state.isCancellable {
            Button("取消当前任务") {
                appCoordinator.sessionCoordinator.cancel()
            }
            Divider()
        }

        Button("打开设置...") {
            openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("查看最近结果") {
            // Placeholder — will be implemented in E9
        }
        .disabled(true)

        Button("清空最近记录") {
            appCoordinator.clearHistory()
        }

        Divider()

        Button("退出 Typoless") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
