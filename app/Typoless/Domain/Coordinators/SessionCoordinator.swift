import AppKit
import Foundation

/// 主链路会话编排器，负责录音、识别、润色、注入的串行调度
@MainActor
@Observable
final class SessionCoordinator {
    private(set) var state: SessionState = .idle
    private(set) var lastRecordedAudio: Data?
    private(set) var currentError: TypolessError?
    private(set) var lastResult: SessionResult?
    private(set) var targetApplicationPID: pid_t?
    private(set) var targetApplicationBundleID: String?

    private let audioRecorder = AudioRecorder()
    private let permissionsManager: PermissionsManager
    private let configStore: ConfigStore
    private let recentRecordStore: RecentRecordStore
    private let textInjector = TextInjector()

    private var timeoutTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?
    private var sessionGeneration: UInt64 = 0

    init(permissionsManager: PermissionsManager, configStore: ConfigStore, recentRecordStore: RecentRecordStore) {
        self.permissionsManager = permissionsManager
        self.configStore = configStore
        self.recentRecordStore = recentRecordStore
    }

    /// 开始录音
    func startRecording() {
        guard state == .idle else { return }

        currentError = nil
        lastResult = nil
        targetApplicationPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        targetApplicationBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        sessionGeneration &+= 1

        do {
            try permissionsManager.ensureMicrophoneAuthorized()
            state = .recording
            try audioRecorder.startRecording()
        } catch {
            handleError(mapError(error))
            return
        }

        // 30 秒超时自动结束
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AudioRecorder.maxDuration))
            guard !Task.isCancelled else { return }
            self?.finishRecording()
        }
    }

    /// 结束录音并开始处理链路
    func finishRecording() {
        guard state == .recording else { return }

        timeoutTask?.cancel()
        timeoutTask = nil

        let audioData = audioRecorder.stopRecording()
        lastRecordedAudio = audioData

        guard !audioData.isEmpty else {
            handleError(.asrEmptyAudio)
            return
        }

        let gen = sessionGeneration
        state = .transcribing

        processingTask = Task { [weak self] in
            await self?.processAudio(audioData, generation: gen)
            self?.processingTask = nil
        }
    }

    /// 取消当前任务
    func cancel() {
        switch state {
        case .recording:
            timeoutTask?.cancel()
            timeoutTask = nil
            _ = audioRecorder.stopRecording()
            lastRecordedAudio = nil
            targetApplicationPID = nil
            targetApplicationBundleID = nil
            state = .cancelled
            scheduleResetToIdle()
        case .transcribing, .polishing:
            sessionGeneration &+= 1
            processingTask?.cancel()
            processingTask = nil
            targetApplicationPID = nil
            targetApplicationBundleID = nil
            state = .cancelled
            scheduleResetToIdle()
        default:
            break
        }
    }

    // MARK: - Processing Pipeline

    private func processAudio(_ audioData: Data, generation: UInt64) async {
        // 1. 使用本地 FunASR 识别
        let asrProvider: any ASRProvider = FunASRProvider()

        let transcriptResult: TranscriptResult
        do {
            transcriptResult = try await asrProvider.recognize(audioData: audioData)
        } catch {
            guard generation == sessionGeneration, !Task.isCancelled else { return }
            handleError(mapError(error))
            return
        }

        guard generation == sessionGeneration, !Task.isCancelled else { return }

        // 2. LLM 润色（如果开启）
        var finalText = transcriptResult.text
        var polishSource: PolishResult.Source = .fallback

        if configStore.generalConfig.enableAIPolish {
            state = .polishing

            let llmProvider = LLMProvider(
                baseURL: configStore.llmConfig.baseURL,
                apiKey: configStore.openAIAPIKey,
                model: configStore.llmConfig.model
            )

            do {
                let polishResult = try await llmProvider.polish(text: transcriptResult.text)
                guard generation == sessionGeneration, !Task.isCancelled else { return }

                if !polishResult.text.isEmpty {
                    finalText = polishResult.text
                    polishSource = .llm
                }
            } catch {
                // LLM 失败：回退到 ASR 原文继续注入
                guard generation == sessionGeneration, !Task.isCancelled else { return }
                polishSource = .fallback
            }
        }

        // 3. 文本注入
        guard generation == sessionGeneration, !Task.isCancelled else { return }
        state = .injecting

        let polishAttempted = configStore.generalConfig.enableAIPolish
        lastResult = SessionResult(text: finalText, source: polishSource, polishAttempted: polishAttempted)

        do {
            try textInjector.inject(
                text: finalText,
                targetPID: targetApplicationPID,
                targetBundleID: targetApplicationBundleID,
                pasteboardPreferredBundleIDs: configStore.generalConfig.effectivePasteboardInjectionBundleIDs
            )
        } catch {
            guard generation == sessionGeneration else { return }
            saveRecord(status: .failed)
            handleError(mapError(error))
            return
        }

        guard generation == sessionGeneration else { return }
        let recordStatus: RecentRecord.RecordStatus = (polishAttempted && polishSource == .fallback) ? .fallbackSuccess : .success
        saveRecord(status: recordStatus)
        state = .done
        scheduleResetToIdle()
    }

    // MARK: - Error Handling

    private func handleError(_ error: TypolessError) {
        currentError = error
        state = .error
        scheduleResetToIdle()
    }

    private func mapError(_ error: Error) -> TypolessError {
        if let te = error as? TypolessError { return te }
        if let pe = error as? PermissionError {
            switch pe {
            case .microphonePermissionDenied: return .microphonePermissionDenied
            case .accessibilityPermissionDenied: return .accessibilityPermissionDenied
            }
        }
        return .textInjectionFailure(detail: error.localizedDescription)
    }

    private func saveRecord(status: RecentRecord.RecordStatus) {
        guard let result = lastResult else { return }
        let record = RecentRecord(
            id: UUID(),
            text: result.text,
            timestamp: Date(),
            status: status
        )
        recentRecordStore.add(record)
    }

    private func scheduleResetToIdle() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self else { return }
            guard self.state == .error || self.state == .cancelled || self.state == .done else { return }
            self.state = .idle
            self.targetApplicationPID = nil
            self.targetApplicationBundleID = nil
        }
    }
}

// MARK: - Session Result

struct SessionResult: Sendable {
    let text: String
    let source: PolishResult.Source
    let polishAttempted: Bool
}
