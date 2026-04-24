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
            "辅助功能权限未开启，无法注入文本"
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
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            microphoneStatus = .notDetermined
        case .authorized:
            microphoneStatus = .granted
        case .denied:
            microphoneStatus = .denied
        case .restricted:
            microphoneStatus = .restricted
        @unknown default:
            microphoneStatus = .denied
        }
    }

    /// 请求麦克风权限（仅 .notDetermined 时有效）
    func requestMicrophonePermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphoneStatus = granted ? .granted : .denied
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

    /// 直接打开系统设置 → 隐私与安全 → 辅助功能
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 打开系统设置 → 隐私与安全 → 麦克风
    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
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

    /// 确保辅助功能权限已授予，否则抛出错误
    func ensureAccessibilityAuthorized() throws {
        checkAccessibilityPermission()
        guard accessibilityStatus == .granted else {
            throw PermissionError.accessibilityPermissionDenied
        }
    }
}
