import SwiftUI

struct SettingsView: View {
    @Bindable var appCoordinator: AppCoordinator

    var body: some View {
        Form {
            GeneralSettingsView(configStore: appCoordinator.configStore, onHotkeyChanged: {
                appCoordinator.setupHotkey()
            })
            LLMSettingsView(configStore: appCoordinator.configStore)
            PermissionsSettingsView(permissionsManager: appCoordinator.permissionsManager)
            ClipboardWhitelistSettingsView(configStore: appCoordinator.configStore)
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 600)
    }
}
