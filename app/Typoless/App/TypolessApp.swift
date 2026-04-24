import SwiftUI

@main
struct TypolessApp: App {
    @State private var appCoordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appCoordinator: appCoordinator)
        } label: {
            Image(systemName: appCoordinator.sessionCoordinator.state.iconName)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(configStore: appCoordinator.configStore)
        }
    }

    init() {
        // 首次启动检查放在 onAppear 等同位置不可靠，使用 DispatchQueue 保证时序
        DispatchQueue.main.async { [appCoordinator] in
            appCoordinator.handleAppLaunch()
        }
    }
}
