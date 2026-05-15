import SwiftUI

struct AboutView: View {
    @Bindable var appCoordinator: AppCoordinator
    private let githubURL = URL(string: "https://github.com/isecret/typoless")!

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            Text("Typoless")
                .font(.title)
                .fontWeight(.semibold)

            VStack(spacing: 4) {
                Text("版本 \(appVersion)")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Toggle(
                "自动检查更新",
                isOn: Binding(
                    get: { appCoordinator.updateService.automaticallyChecksForUpdates },
                    set: { appCoordinator.updateService.setAutomaticallyChecksForUpdates($0) }
                )
            )
            .toggleStyle(.checkbox)

            Button("检查更新") {
                appCoordinator.updateService.checkForUpdates()
            }
            .disabled(!appCoordinator.updateService.canCheckForUpdates)

            Link(destination: githubURL) {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                    Text("GitHub")
                }
            }
        }
        .padding(32)
        .frame(width: 320)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}
