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

    /// 最近一次注入失败的文本，仅内存态，供菜单栏复制使用
    private(set) var lastInjectionFailureText: String?

    /// 反馈事件回调，由 HUDFeedbackController 设置
    var onFeedbackEvent: (@MainActor @Sendable (SessionFeedbackEvent) -> Void)?

    /// 返回当前音频录制电平（0-1），供 HUD 声波动画使用
    func currentAudioLevel() -> Float {
        audioRecorder.currentLevel()
    }

    private let audioRecorder = AudioRecorder()
    private let audioPreprocessor = AudioPreprocessor()
    private let permissionsManager: PermissionsManager
    private let configStore: ConfigStore
    private let textInjector = TextInjector()
    private let diagnostics = DiagnosticsLogger.shared

    private var timeoutTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?
    private var sessionGeneration: UInt64 = 0
    private var currentSessionID: String = ""

    init(permissionsManager: PermissionsManager, configStore: ConfigStore, dictionaryStore: PersonalDictionaryStore? = nil) {
        self.permissionsManager = permissionsManager
        self.configStore = configStore
        self.dictionaryStore = dictionaryStore
    }

    private let dictionaryStore: PersonalDictionaryStore?

    /// 开始录音
    func startRecording() {
        guard state == .idle else { return }

        currentError = nil
        lastResult = nil
        targetApplicationPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        targetApplicationBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        sessionGeneration &+= 1
        currentSessionID = Self.generateSessionID()

        do {
            try permissionsManager.ensureMicrophoneAuthorized()
            state = .recording
            try audioRecorder.startRecording()
            diagnostics.sessionStarted(
                sessionID: currentSessionID,
                targetBundleID: targetApplicationBundleID
            )
            onFeedbackEvent?(.recordingStarted)
        } catch {
            handleError(mapError(error))
            return
        }

        // 60 秒超时自动结束
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

        let recordingResult = audioRecorder.stopRecording()
        let audioData = recordingResult.data
        lastRecordedAudio = audioData
        onFeedbackEvent?(.recordingStopped)

        // 短录音静默取消（<500ms）
        if recordingResult.isShortRecording {
            diagnostics.shortRecordingCancelled(
                sessionID: currentSessionID,
                durationMs: recordingResult.durationMs
            )
            lastRecordedAudio = nil
            targetApplicationPID = nil
            targetApplicationBundleID = nil
            state = .idle
            return
        }

        guard !audioData.isEmpty else {
            handleError(.asrEmptyAudio)
            return
        }

        let gen = sessionGeneration
        let sessionID = currentSessionID
        let recordingMs = recordingResult.durationMs
        state = .transcribing

        processingTask = Task { [weak self] in
            await self?.processAudio(
                audioData,
                generation: gen,
                sessionID: sessionID,
                recordingMs: recordingMs
            )
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
            diagnostics.sessionCancelled(sessionID: currentSessionID)
            onFeedbackEvent?(.processingCancelled)
            scheduleResetToIdle()
        case .transcribing, .polishing:
            sessionGeneration &+= 1
            processingTask?.cancel()
            processingTask = nil
            targetApplicationPID = nil
            targetApplicationBundleID = nil
            state = .cancelled
            diagnostics.sessionCancelled(sessionID: currentSessionID)
            onFeedbackEvent?(.processingCancelled)
            scheduleResetToIdle()
        default:
            break
        }
    }

    // MARK: - Processing Pipeline

    private func processAudio(
        _ audioData: Data,
        generation: UInt64,
        sessionID: String,
        recordingMs: Int
    ) async {
        let sessionStart = Date()
        var diag = SessionDiagnostics()
        diag.recordingMs = recordingMs
        diag.targetBundleID = targetApplicationBundleID

        // 1. 音频降噪
        let denoiseStart = Date()
        let processedAudio: Data
        do {
            processedAudio = try audioPreprocessor.denoise(wavData: audioData)
            let denoiseMs = Int(Date().timeIntervalSince(denoiseStart) * 1000)
            diag.denoiseMs = denoiseMs
            diagnostics.denoiseCompleted(sessionID: sessionID, durationMs: denoiseMs)
        } catch {
            guard generation == sessionGeneration, !Task.isCancelled else { return }
            let denoiseMs = Int(Date().timeIntervalSince(denoiseStart) * 1000)
            diag.denoiseMs = denoiseMs
            let mapped = mapError(error)
            diag.totalMs = Int(Date().timeIntervalSince(sessionStart) * 1000)
            diag.errorClassification = mapped.diagnosticClassification
            diagnostics.denoiseFailed(sessionID: sessionID, reason: mapped.diagnosticClassification)
            diagnostics.sessionEnded(sessionID: sessionID, result: diag)
            handleError(mapped)
            return
        }

        guard generation == sessionGeneration, !Task.isCancelled else { return }

        // 2. 使用本地 Whisper 识别
        let asrProvider: any ASRProvider = WhisperProvider()

        let asrStart = Date()
        let transcriptResult: TranscriptResult
        do {
            transcriptResult = try await asrProvider.recognize(audioData: processedAudio)
        } catch {
            guard generation == sessionGeneration, !Task.isCancelled else { return }
            let mapped = mapError(error)
            diag.asrMs = Int(Date().timeIntervalSince(asrStart) * 1000)
            diag.totalMs = Int(Date().timeIntervalSince(sessionStart) * 1000)
            diag.errorClassification = mapped.diagnosticClassification
            diagnostics.sessionError(sessionID: sessionID, error: mapped)
            diagnostics.sessionEnded(sessionID: sessionID, result: diag)
            handleError(mapped)
            return
        }

        guard generation == sessionGeneration, !Task.isCancelled else { return }

        let asrMs = Int(Date().timeIntervalSince(asrStart) * 1000)
        diag.asrMs = asrMs
        diagnostics.asrCompleted(
            sessionID: sessionID,
            text: transcriptResult.text,
            durationMs: asrMs
        )

        // 2. LLM 润色（如果开启）
        var finalText = transcriptResult.text
        var polishSource: PolishResult.Source = .fallback

        if configStore.generalConfig.enableAIPolish {
            state = .polishing

            let terms = await MainActor.run { dictionaryStore?.termsForPrompt() ?? [] }
            let llmProvider = LLMProvider(
                baseURL: configStore.llmConfig.baseURL,
                apiKey: configStore.openAIAPIKey,
                model: configStore.llmConfig.model,
                dictionaryTerms: terms
            )

            let llmStart = Date()
            do {
                let polishResult = try await llmProvider.polish(text: transcriptResult.text)
                guard generation == sessionGeneration, !Task.isCancelled else { return }

                let llmMs = Int(Date().timeIntervalSince(llmStart) * 1000)
                diag.llmMs = llmMs

                if !polishResult.text.isEmpty {
                    finalText = polishResult.text
                    polishSource = .llm
                }
                diagnostics.llmCompleted(
                    sessionID: sessionID,
                    text: finalText,
                    source: polishSource.rawValue,
                    durationMs: llmMs
                )
            } catch {
                // LLM 失败：回退到 ASR 原文继续注入
                guard generation == sessionGeneration, !Task.isCancelled else { return }
                let llmMs = Int(Date().timeIntervalSince(llmStart) * 1000)
                diag.llmMs = llmMs
                polishSource = .fallback

                let reason: String
                if let te = error as? TypolessError {
                    reason = te.diagnosticClassification
                } else {
                    reason = error.localizedDescription
                }
                diagnostics.llmFallback(sessionID: sessionID, reason: reason)
            }
        }

        // 3. 文本注入
        guard generation == sessionGeneration, !Task.isCancelled else { return }
        state = .injecting
        diag.resultSource = polishSource.rawValue

        let polishAttempted = configStore.generalConfig.enableAIPolish
        lastResult = SessionResult(text: finalText, source: polishSource, polishAttempted: polishAttempted)

        let injectionStart = Date()
        do {
            try textInjector.inject(
                text: finalText,
                targetPID: targetApplicationPID,
                targetBundleID: targetApplicationBundleID,
                pasteboardPreferredBundleIDs: configStore.generalConfig.effectivePasteboardInjectionBundleIDs
            )
        } catch {
            guard generation == sessionGeneration else { return }
            diag.injectionMs = Int(Date().timeIntervalSince(injectionStart) * 1000)
            diag.totalMs = Int(Date().timeIntervalSince(sessionStart) * 1000)
            diag.errorClassification = mapError(error).diagnosticClassification
            diagnostics.sessionError(sessionID: sessionID, error: mapError(error))
            diagnostics.sessionEnded(sessionID: sessionID, result: diag)
            lastInjectionFailureText = finalText
            handleError(mapError(error))
            return
        }

        guard generation == sessionGeneration else { return }
        diag.injectionMs = Int(Date().timeIntervalSince(injectionStart) * 1000)
        diag.totalMs = Int(Date().timeIntervalSince(sessionStart) * 1000)

        lastInjectionFailureText = nil
        state = .done
        diagnostics.sessionEnded(sessionID: sessionID, result: diag)
        onFeedbackEvent?(.processingFinished)
        scheduleResetToIdle()
    }

    // MARK: - Error Handling

    private func handleError(_ error: TypolessError) {
        currentError = error
        state = .error
        onFeedbackEvent?(.processingFailed)
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

    // MARK: - Helpers

    private static func generateSessionID() -> String {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000) % 100_000_000
        let random = Int.random(in: 0..<0xFFFF)
        return String(format: "%08x-%04x", timestamp, random)
    }
}

// MARK: - Session Result

struct SessionResult: Sendable {
    let text: String
    let source: PolishResult.Source
    let polishAttempted: Bool
}
