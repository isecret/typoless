import Foundation

/// 主链路会话编排器（E1 仅提供状态骨架，完整实现在 E8）
@MainActor
@Observable
final class SessionCoordinator {
    private(set) var state: SessionState = .idle

    /// 取消当前处理中的任务
    func cancel() {
        guard state.isCancellable else { return }
        state = .cancelled
        Task {
            try? await Task.sleep(for: .seconds(1))
            if state == .cancelled {
                state = .idle
            }
        }
    }
}
