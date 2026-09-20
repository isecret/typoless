import AVFoundation
import ApplicationServices
import AppKit
import Foundation

// MARK: - Permission Status

enum MicrophonePermission: String, Sendable {
    case notDetermined
    case granted
    case denied
    case restricted
}

enum AccessibilityPermission: String, Sendable {
    case granted
    case requiresManualEnable
}

// MARK: - Permission Errors

enum PermissionError: LocalizedError, Equatable, Sendable {
    case microphonePermissionDenied
    case accessibilityPermissionDenied

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "麦克风权限未开启，无法录音"
        case .accessibilityPermissionDenied:
            "辅助功能权限未开启，无法开始录音"
        }
    }
}

@MainActor
protocol VoiceInputPermissionPreparing: AnyObject {
    var isPreparingVoiceInputPermissions: Bool { get }
    func prepareForVoiceInputStart() async throws
}

// MARK: - PermissionsManager

/// 管理麦克风与辅助功能权限的检测、申请与引导
@MainActor
@Observable
final class PermissionsManager: VoiceInputPermissionPreparing {

    private(set) var microphoneStatus: MicrophonePermission = .notDetermined
    private(set) var accessibilityStatus: AccessibilityPermission = .requiresManualEnable
    private(set) var isRequestingMicrophonePermission = false
    private(set) var isPreparingVoiceInputPermissions = false

    init() {
        refreshAll()
    }

    // MARK: - Refresh

    func refreshAll() {
        checkMicrophonePermission()
        checkAccessibilityPermission()
    }

    // MARK: - Microphone

    func checkMicrophonePermission() {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined:
            microphoneStatus = .notDetermined
        case .granted:
            microphoneStatus = .granted
        case .denied:
            microphoneStatus = .denied
        @unknown default:
            microphoneStatus = .denied
        }
    }

    /// 请求麦克风权限（仅 .notDetermined 时有效）
    func requestMicrophonePermission() async {
        checkMicrophonePermission()
        guard microphoneStatus == .notDetermined, !isRequestingMicrophonePermission else { return }

        isRequestingMicrophonePermission = true
        NSApp.activate(ignoringOtherApps: true)
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { _ in
                continuation.resume()
            }
        }
        isRequestingMicrophonePermission = false
        checkMicrophonePermission()
    }

    /// 首次语音输入启动前的权限编排。
    ///
    /// 麦克风优先：未决定时弹系统授权；已拒绝/受限时打开隐私设置。
    /// 辅助功能随后检查：未授权时触发系统引导。任何缺失都会阻止本次录音。
    func prepareForVoiceInputStart() async throws {
        if isPreparingVoiceInputPermissions {
            while isPreparingVoiceInputPermissions {
                try await Task.sleep(for: .milliseconds(50))
            }
            try ensureMicrophoneAuthorized()
            try ensureAccessibilityAuthorized()
            return
        }

        isPreparingVoiceInputPermissions = true
        defer {
            isPreparingVoiceInputPermissions = false
            refreshAll()
        }

        checkMicrophonePermission()
        switch microphoneStatus {
        case .notDetermined:
            await requestMicrophonePermission()
            guard microphoneStatus == .granted else {
                throw PermissionError.microphonePermissionDenied
            }
        case .granted:
            break
        case .denied, .restricted:
            openMicrophoneSettings()
            throw PermissionError.microphonePermissionDenied
        }

        checkAccessibilityPermission()
        guard accessibilityStatus == .granted else {
            promptAndOpenAccessibilitySettings()
            throw PermissionError.accessibilityPermissionDenied
        }
    }

    // MARK: - Enforcement APIs (供 E4/E7/E8 使用)

    /// 确保麦克风权限已授予，否则抛出错误
    func ensureMicrophoneAuthorized() throws {
        checkMicrophonePermission()
        guard microphoneStatus == .granted else {
            throw PermissionError.microphonePermissionDenied
        }
    }

    // MARK: - Accessibility

    func checkAccessibilityPermission() {
        accessibilityStatus = AXIsProcessTrusted() ? .granted : .requiresManualEnable
    }

    /// 显示系统辅助功能权限弹窗并打开设置
    func promptAndOpenAccessibilitySettings() {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        checkAccessibilityPermission()
    }

    /// 打开系统设置 → 隐私与安全 → 麦克风
    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 确保辅助功能权限已授予，否则抛出错误
    func ensureAccessibilityAuthorized() throws {
        checkAccessibilityPermission()
        guard accessibilityStatus == .granted else {
            throw PermissionError.accessibilityPermissionDenied
        }
    }
}
