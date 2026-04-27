import SwiftUI

@main
struct TypolessApp: App {
    @State private var appCoordinator: AppCoordinator

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appCoordinator: appCoordinator)
        } label: {
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.menu)

        Window("关于 Typoless", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    init() {
        let coordinator = AppCoordinator()
        _appCoordinator = State(initialValue: coordinator)

        // 首次启动检查放在 onAppear 等同位置不可靠，使用 DispatchQueue 保证时序
        DispatchQueue.main.async {
            coordinator.handleAppLaunch()
        }
    }
}
