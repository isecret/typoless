import SwiftUI

struct MenuBarView: View {
    let appCoordinator: AppCoordinator
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    private var state: SessionState {
        appCoordinator.sessionCoordinator.state
    }

    private var records: [RecentRecord] {
        appCoordinator.recentRecordStore.records
    }

    var body: some View {
        if let error = appCoordinator.sessionCoordinator.currentError {
            Text(error.userMessage)
                .foregroundStyle(.secondary)

            Divider()
        }

        if state.isCancellable {
            Button("取消当前任务") {
                appCoordinator.sessionCoordinator.cancel()
            }
            Divider()
        }

        // MARK: - 最近记录（直接平铺）

        if records.isEmpty {
            Text("暂无记录")
                .foregroundStyle(.secondary)
        } else {
            ForEach(records.prefix(5)) { record in
                let preview = record.text.count > 40
                    ? String(record.text.prefix(40)) + "…"
                    : record.text
                Button(preview) {
                    appCoordinator.reinjectText(record.text)
                }
            }
        }

        Button("清空最近记录") {
            appCoordinator.clearHistory()
        }
        .disabled(records.isEmpty)

        Divider()

        Button("设置") {
            openSettings()
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
