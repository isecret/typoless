import SwiftUI

struct PermissionsSettingsView: View {
    let permissionsManager: PermissionsManager

    var body: some View {
        // MARK: - 麦克风权限
        Section("麦克风权限") {
            HStack(spacing: 8) {
                PermissionStatusBadge(granted: permissionsManager.microphoneStatus == .granted)
                Text(microphoneStatusText)
                Spacer()
                microphoneActionButton
            }
            Text("用于录制语音并发送至 ASR 服务进行识别。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }

        // MARK: - 辅助功能权限
        Section("辅助功能权限") {
            HStack(spacing: 8) {
                PermissionStatusBadge(granted: permissionsManager.accessibilityStatus == .granted)
                Text(accessibilityStatusText)
                Spacer()
                accessibilityActionButton
            }
            Text("用于将识别结果注入到当前焦点应用的输入框。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .onAppear {
            permissionsManager.refreshAll()
        }
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

    @ViewBuilder
    private var microphoneActionButton: some View {
        switch permissionsManager.microphoneStatus {
        case .notDetermined:
            Button("请求权限") {
                Task {
                    await permissionsManager.requestMicrophonePermission()
                }
            }
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
