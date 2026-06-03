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
                Text("用于文本注入；部分场景会读取有限上下文，敏感场景会自动脱敏。")
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
            "用于录制语音并发送至 ASR 服务进行识别。"
        case .denied:
            "系统当前已拒绝 Typoless 的麦克风权限。请前往系统设置恢复授权后再返回应用。"
        case .restricted:
            "麦克风权限受系统策略控制，Typoless 无法直接发起授权。"
        case .granted:
            "用于录制语音并发送至 ASR 服务进行识别。"
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
