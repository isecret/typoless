import SwiftUI

struct DiagnosticsView: View {
    let sessionCoordinator: SessionCoordinator

    var body: some View {
        Form {
            Section("当前状态") {
                LabeledContent("会话状态") {
                    HStack(spacing: 4) {
                        Image(systemName: sessionCoordinator.state.iconName)
                        Text(sessionCoordinator.state.displayText)
                    }
                }
            }

            Section("最近一次错误") {
                if let error = sessionCoordinator.currentError {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error.userMessage)
                            .foregroundStyle(.primary)
                    }
                } else {
                    Text("无错误")
                        .foregroundStyle(.secondary)
                }
            }

            Section("应用信息") {
                LabeledContent("版本") {
                    Text(appVersion)
                }
                LabeledContent("系统要求") {
                    Text("macOS 14.0+")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}
