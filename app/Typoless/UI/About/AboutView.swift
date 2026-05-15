import SwiftUI

struct AboutView: View {
    @Bindable var appCoordinator: AppCoordinator
    private let githubURL = URL(string: "https://github.com/isecret/typoless")!

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            Text("Typoless")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 4) {
                Text("版本 \(appVersion)")
                    .font(.subheadline)
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
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .frame(width: 252)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}
