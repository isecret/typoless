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
            SettingsView()
        }
    }
}
