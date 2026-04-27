import SwiftUI

struct AboutView: View {
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
                Text("构建 \(buildNumber)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Link(destination: githubURL) {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                    Text("GitHub")
                }
            }
        }
        .padding(32)
        .frame(width: 280)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}
