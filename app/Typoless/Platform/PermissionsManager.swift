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

// MARK: - PermissionsManager

/// 管理麦克风与辅助功能权限的检测、申请与引导
@MainActor
@Observable
final class PermissionsManager {

    private(set) var microphoneStatus: MicrophonePermission = .notDetermined
    private(set) var accessibilityStatus: AccessibilityPermission = .requiresManualEnable
    private(set) var isRequestingMicrophonePermission = false

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
