import Foundation

/// 应用生命周期协调器，负责菜单栏入口与设置页管理
@MainActor
@Observable
final class AppCoordinator {
    let sessionCoordinator = SessionCoordinator()

    /// 清空最近记录（E9 实现）
    func clearHistory() {
        // Placeholder — will be implemented in E9
    }
}
