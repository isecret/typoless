import SwiftUI

struct MenuBarView: View {
    let appCoordinator: AppCoordinator
    @Environment(\.openSettings) private var openSettings

    private var state: SessionState {
        appCoordinator.sessionCoordinator.state
    }

    private var records: [RecentRecord] {
        appCoordinator.recentRecordStore.records
    }

    var body: some View {
        Text("当前状态：\(state.displayText)")

        if let error = appCoordinator.sessionCoordinator.currentError {
            Text(error.userMessage)
                .foregroundStyle(.secondary)
        }

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

        // 最近结果子菜单
        if !records.isEmpty {
            Menu("最近结果") {
                ForEach(records.prefix(5)) { record in
                    let preview = record.text.count > 30
                        ? String(record.text.prefix(30)) + "…"
                        : record.text
                    Button(preview) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(record.text, forType: .string)
                    }
                }
                Divider()
                Button("查看全部记录...") {
                    appCoordinator.openSettings(tab: .recentRecords)
                }
            }
        } else {
            Button("查看最近结果") {}
                .disabled(true)
        }

        Button("清空最近记录") {
            appCoordinator.clearHistory()
        }
        .disabled(records.isEmpty)

        Divider()

        Button("退出 Typoless") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
