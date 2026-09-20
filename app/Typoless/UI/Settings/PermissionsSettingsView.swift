import SwiftUI

struct PermissionsSettingsView: View {
    let permissionsManager: PermissionsManager

    var body: some View {
        Group {
            SettingsPaneSection {
                SettingsFormRow(title: "麦克风权限") {
                    HStack(spacing: 8) {
                        PermissionStatusBadge(granted: permissionsManager.microphoneStatus == .granted)
                        Text(microphoneStatusText)
                            .foregroundStyle(.secondary)
                        Spacer()
                        microphoneActionButton
                    }
                    .frame(width: SettingsFormLayout.controlWidth, alignment: .leading)
                }
            } footer: {
                Text(microphoneDescription)
            }

            SettingsPaneSection {
                SettingsFormRow(title: "辅助功能权限") {
                    HStack(spacing: 8) {
                        PermissionStatusBadge(granted: permissionsManager.accessibilityStatus == .granted)
                        Text(accessibilityStatusText)
                            .foregroundStyle(.secondary)
                        Spacer()
                        accessibilityActionButton
                    }
                    .frame(width: SettingsFormLayout.controlWidth, alignment: .leading)
                }
            } footer: {
                Text("用于向其他应用写入文字，也可能读取输入框附近的少量文字；密码框等敏感场景不会发送输入内容。")
            }
        }
        .onAppear { permissionsManager.refreshAll() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionsManager.refreshAll()
        }
    }

    // MARK: - Microphone

    private var microphoneStatusText: String {
        switch permissionsManager.microphoneStatus {
        case .notDetermined: "尚未请求"
        case .granted: "已授权"
        case .denied: "已拒绝"
        case .restricted: "受限（由系统策略控制）"
        }
    }

    private var microphoneDescription: String {
        switch permissionsManager.microphoneStatus {
        case .notDetermined:
            "用于录音。选择云端语音引擎时，录音会发送到对应服务识别。"
        case .denied:
            "麦克风权限已关闭。请在系统设置中为 Typoless 开启麦克风权限。"
        case .restricted:
            "系统限制了麦克风权限，无法在 Typoless 中开启。"
        case .granted:
            "用于录音。选择云端语音引擎时，录音会发送到对应服务识别。"
        }
    }

    @ViewBuilder
    private var microphoneActionButton: some View {
        switch permissionsManager.microphoneStatus {
        case .notDetermined:
            Button(permissionsManager.isRequestingMicrophonePermission ? "请求中…" : "请求权限") {
                Task {
                    await permissionsManager.requestMicrophonePermission()
                }
            }
            .disabled(permissionsManager.isRequestingMicrophonePermission)
        case .denied, .restricted:
            Button("打开系统设置") {
                permissionsManager.openMicrophoneSettings()
            }
        case .granted:
            EmptyView()
        }
    }

    // MARK: - Accessibility

    private var accessibilityStatusText: String {
        switch permissionsManager.accessibilityStatus {
        case .granted: "已授权"
        case .requiresManualEnable: "未授权"
        }
    }

    @ViewBuilder
    private var accessibilityActionButton: some View {
        switch permissionsManager.accessibilityStatus {
        case .requiresManualEnable:
            Button("打开系统设置") {
                permissionsManager.promptAndOpenAccessibilitySettings()
            }
        case .granted:
            EmptyView()
        }
    }
}

// MARK: - Status Badge

private struct PermissionStatusBadge: View {
    let granted: Bool

    var body: some View {
        Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(granted ? .green : .red)
            .imageScale(.large)
    }
}
