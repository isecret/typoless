import SwiftUI

struct SettingsView: View {
    @Bindable var appCoordinator: AppCoordinator

    var body: some View {
        Form {
            LLMSettingsView(configStore: appCoordinator.configStore)
            GeneralSettingsView(configStore: appCoordinator.configStore, onHotkeyChanged: {
                appCoordinator.setupHotkey()
            })
            PermissionsSettingsView(permissionsManager: appCoordinator.permissionsManager)
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 600)
    }
}
