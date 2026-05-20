import ServiceManagement

/// 使用 macOS 登录项（SMAppService）管理开机启动，需 macOS 13+
final class LaunchAtLoginManager {
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
