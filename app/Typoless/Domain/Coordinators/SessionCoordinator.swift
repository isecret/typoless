import Foundation

/// 主链路会话编排器，负责录音、识别、润色、注入的串行调度
@MainActor
@Observable
final class SessionCoordinator {
    private(set) var state: SessionState = .idle
    private(set) var lastRecordedAudio: Data?

    private let audioRecorder = AudioRecorder()
    private let permissionsManager: PermissionsManager
    private var timeoutTask: Task<Void, Never>?

    init(permissionsManager: PermissionsManager) {
        self.permissionsManager = permissionsManager
    }

    /// 开始录音
    func startRecording() {
        guard state == .idle else { return }

        do {
            try permissionsManager.ensureMicrophoneAuthorized()
            state = .recording
            try audioRecorder.startRecording()
        } catch {
            state = .error
            scheduleResetToIdle()
            return
        }

        // 30 秒超时自动结束
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AudioRecorder.maxDuration))
            guard !Task.isCancelled else { return }
            self?.finishRecording()
        }
    }

    /// 结束录音
    func finishRecording() {
        guard state == .recording else { return }

        timeoutTask?.cancel()
        timeoutTask = nil

        let audioData = audioRecorder.stopRecording()
        lastRecordedAudio = audioData

        // E5/E8 将在此处推进到 .transcribing
        state = .idle
    }

    /// 取消当前任务
    func cancel() {
        switch state {
        case .recording:
            timeoutTask?.cancel()
            timeoutTask = nil
            _ = audioRecorder.stopRecording()
            lastRecordedAudio = nil
            state = .cancelled
            scheduleResetToIdle()
        case .transcribing, .polishing:
            // E5/E8 将补充 ASR/LLM 取消逻辑
            state = .cancelled
            scheduleResetToIdle()
        default:
            break
        }
    }

    private func scheduleResetToIdle() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, self.state == .error || self.state == .cancelled else { return }
            self.state = .idle
        }
    }
}
