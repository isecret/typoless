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
    private let audioDeviceManager: AudioDeviceManager
    private let textInjector = TextInjector()
    private let diagnostics = DiagnosticsLogger.shared

    /// FunASR sidecar 运行时管理器，跨 session 复用
    private let asrRuntimeManager = ASRRuntimeManager()

    private var processingTask: Task<Void, Never>?
    private var resetToIdleTask: Task<Void, Never>?
    private var soundCueTask: Task<Void, Never>?
    private var sessionGeneration: UInt64 = 0
    private var currentSessionID: String = ""
    private var processingMode: TextProcessingMode = .polish

    // 分段相关
    private let segmenter = AudioSegmenter()
    private var segmentStream: AsyncStream<SealedSegment>?
    private var segmentContinuation: AsyncStream<SealedSegment>.Continuation?

    init(
        permissionsManager: PermissionsManager,
        configStore: ConfigStore,
        audioDeviceManager: AudioDeviceManager,
        dictionaryStore: PersonalDictionaryStore? = nil
    ) {
        self.permissionsManager = permissionsManager
        self.configStore = configStore
        self.audioDeviceManager = audioDeviceManager
        self.dictionaryStore = dictionaryStore
    }

    private let dictionaryStore: PersonalDictionaryStore?

    /// 开始录音
    func startRecording() {
        guard state.allowsRecordingStart else { return }

        if state != .idle {
            resetToIdleTask?.cancel()
            resetToIdleTask = nil
            state = .idle
            targetApplicationPID = nil
            targetApplicationBundleID = nil
        }

        currentError = nil
        lastResult = nil
        targetApplicationPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        targetApplicationBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        sessionGeneration &+= 1
        currentSessionID = Self.generateSessionID()
        let selectedPlatform = configStore.asrConfig.selectedPlatform
        let sessionID = currentSessionID
        let targetBundleID = targetApplicationBundleID

        do {
            configStore.refreshLocalModelStatusFromDisk()
            try permissionsManager.ensureMicrophoneAuthorized()
            try ResourceValidator.validateDenoiseResources()
            // 录音前检查 ASR 平台可用性
            guard configStore.isASRReady else {
                throw TypolessError.asrPlatformNotReady(detail: configStore.asrNotReadyReason ?? "未知")
            }
            // 本地 FunASR 额外校验运行时资源
            if configStore.asrConfig.selectedPlatform == .localFunASR {
                try ResourceValidator.validateASRResources()
            }
            state = .recording
            processingMode = .polish
            onFeedbackEvent?(.recordingStarted)

            beginRecording(
                generation: sessionGeneration,
                sessionID: sessionID,
                targetBundleID: targetBundleID,
                selectedPlatform: selectedPlatform
            )
        } catch {
            handleError(mapError(error))
        }
    }

    private func beginRecording(
        generation: UInt64,
        sessionID: String,
        targetBundleID: String?,
        selectedPlatform: ASRPlatform
    ) {
        guard generation == sessionGeneration, state == .recording else { return }

        do {
            // 配置分段器和 AsyncStream
            segmenter.reset()
            let (stream, continuation) = AsyncStream.makeStream(of: SealedSegment.self)
            segmentStream = stream
            segmentContinuation = continuation
            segmenter.onSegmentSealed = { segment in
                continuation.yield(segment)
            }

            // 配置录音器 PCM chunk 回调
            audioRecorder.onPCMChunk = { [segmenter] chunk in
                segmenter.appendPCMChunk(chunk)
            }

            try audioRecorder.startRecording(device: audioDeviceManager.captureDeviceForRecording())
            diagnostics.sessionStarted(
                sessionID: sessionID,
                targetBundleID: targetBundleID
            )

            // 录音器已启动，CoreAudio 硬件已重配置到 16kHz。
            // 等 500ms 让硬件稳定后播放开始音效，避免音效被硬件切换中断。
            soundCueTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self, self.state == .recording else { return }
                self.onFeedbackEvent?(.startSoundCue)
            }

            // 本地 FunASR 模式下录音开始即后台预热 ASR worker（不阻塞录音）
            if selectedPlatform == .localFunASR {
                asrRuntimeManager.warmup()
            }
        } catch {
            handleError(mapError(error))
        }
    }

    /// 结束录音并开始处理链路
    func finishRecording() {
        guard state == .recording else { return }

        soundCueTask?.cancel()
        soundCueTask = nil

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
            cleanupSegmenterState()
            state = .idle
            return
        }

        guard !audioData.isEmpty else {
            cleanupSegmenterState()
            handleError(.asrEmptyAudio)
            return
        }

        // 通知分段器结束，触发最终分段
        segmenter.finalize()
        segmentContinuation?.finish()

        let gen = sessionGeneration
        let sessionID = currentSessionID
        let recordingMs = recordingResult.durationMs
        state = .transcribing

        // 在 session 开始时快照配置，保证长录音期间配置一致性
        let asrConfig = configStore.asrConfig
        let selectedPlatform = asrConfig.selectedPlatform
        let llmConfig = configStore.llmConfig
        let openAIAPIKey = configStore.openAIAPIKey
        let isLLMConfigured = configStore.isLLMConfigured
        let hotwords = selectedPlatform == .localFunASR
            ? (dictionaryStore?.hotwordsForFunASR() ?? "")
            : ""
        let terms = dictionaryStore?.termsForPrompt() ?? []
        let currentProcessingMode = processingMode
        let translationTarget = configStore.generalConfig.translationTargetLanguage

        processingTask = Task { [weak self] in
            await self?.processSegmentedAudio(
                generation: gen,
                sessionID: sessionID,
                recordingMs: recordingMs,
                asrConfig: asrConfig,
                selectedPlatform: selectedPlatform,
                llmConfig: llmConfig,
                openAIAPIKey: openAIAPIKey,
                isLLMConfigured: isLLMConfigured,
                hotwords: hotwords,
                terms: terms,
                processingMode: currentProcessingMode,
                translationTarget: translationTarget
            )
            self?.processingTask = nil
        }
    }

    /// 取消当前任务
    func cancel() {
        switch state {
        case .recording:
            soundCueTask?.cancel()
            soundCueTask = nil
            _ = audioRecorder.stopRecording()
            cleanupSegmenterState()
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
            cleanupSegmenterState()
            // 取消期间 worker 可能仍在推理，标记为不可信并销毁，防止旧响应污染后续 session
            if state == .transcribing {
                asrRuntimeManager.invalidateCurrentWorker()
            }
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

    /// 切换当前录音 session 的文本处理模式（仅在录音态生效）
    func toggleProcessingMode() {
        guard state == .recording else { return }
        processingMode = (processingMode == .polish) ? .translate : .polish
        diagnostics.log(sessionID: currentSessionID, event: "processing_mode_changed", detail: processingMode.rawValue)
        onFeedbackEvent?(.modeSwitched(processingMode))
    }

    // MARK: - Segmented Processing Pipeline

    private nonisolated func processSegmentedAudio(
        generation: UInt64,
        sessionID: String,
        recordingMs: Int,
        asrConfig: ASRConfig,
        selectedPlatform: ASRPlatform,
        llmConfig: LLMConfig,
        openAIAPIKey: String,
        isLLMConfigured: Bool,
        hotwords: String,
        terms: [TermReference],
        processingMode: TextProcessingMode,
        translationTarget: TranslationTargetLanguage
    ) async {
        let sessionStart = Date()
        var diag = SessionDiagnostics()
        diag.recordingMs = recordingMs
        diag.targetBundleID = await MainActor.run { targetApplicationBundleID }

        let wasColdStart = asrRuntimeManager.warmupState != .warm

        // 本地 FunASR：等待预热完成
        if selectedPlatform == .localFunASR {
            do {
                try await asrRuntimeManager.awaitWarmupIfNeeded()
            } catch {
                diagnostics.log(sessionID: sessionID, event: "warmup_failed", detail: error.localizedDescription)
            }
        }

        // 构建 ASR Provider
        let asrProviderFactory = ASRProviderFactory(runtimeManager: asrRuntimeManager)
        let asrProvider = asrProviderFactory.makeProvider(for: asrConfig, hotwords: hotwords)

        guard let stream = await MainActor.run(body: { segmentStream }) else { return }

        // 串行处理分段
        var transcripts: [String] = []
        var totalASRMs: Int = 0
        var totalDenoiseMs: Int = 0
        var accumulatedChars: Int = 0
        var segmentDiagList: [SegmentDiagnostics] = []
        var segmentCount = 0
        let maxChars = 8000

        for await segment in stream {
            guard await MainActor.run(body: { sessionGeneration }) == generation,
                  !Task.isCancelled else { return }

            segmentCount += 1

            // 跳过无语音的分段（如纯静音尾段）
            if !segment.voicedDetected {
                diagnostics.log(sessionID: sessionID, event: "segment_skipped_no_voice", detail: "index=\(segment.index)")
                continue
            }

            diagnostics.segmentSealed(
                sessionID: sessionID,
                index: segment.index,
                sampleCount: segment.sampleCount,
                reason: segment.sealReason.rawValue
            )

            // 编码为 WAV
            let wavData = WAVAudioEncoder.encodePCM16(
                pcmData: segment.pcmData,
                sampleRate: AudioSegmenter.sampleRate,
                channels: 1
            )

            // 降噪
            let denoiseStart = Date()
            let processedAudio: Data
            do {
                processedAudio = try audioPreprocessor.denoise(wavData: wavData)
            } catch {
                diagnostics.denoiseFailed(sessionID: sessionID, reason: "segment \(segment.index): \(error.localizedDescription)")
                // 降噪失败时使用原始音频
                processedAudio = wavData
            }
            let denoiseMs = Int(Date().timeIntervalSince(denoiseStart) * 1000)
            totalDenoiseMs += denoiseMs

            guard await MainActor.run(body: { sessionGeneration }) == generation,
                  !Task.isCancelled else { return }

            // ASR 识别（动态超时：每秒音频 0.5 秒处理时间，最少 15 秒）
            let dynamicTimeout = max(15.0, segment.durationSeconds * 0.5 + 10.0)
            let asrStart = Date()
            let transcriptResult: TranscriptResult
            do {
                transcriptResult = try await asrProvider.recognize(audioData: processedAudio, timeout: dynamicTimeout)
                if selectedPlatform == .localFunASR {
                    asrRuntimeManager.markRecognitionSucceeded()
                }
            } catch {
                guard await MainActor.run(body: { sessionGeneration }) == generation,
                      !Task.isCancelled else { return }
                let mapped = await MainActor.run { mapError(error) }
                let asrMs = Int(Date().timeIntervalSince(asrStart) * 1000)
                diag.asrMs = totalASRMs + asrMs
                diag.denoiseMs = totalDenoiseMs
                diag.totalMs = Int(Date().timeIntervalSince(sessionStart) * 1000)
                diag.errorClassification = mapped.diagnosticClassification
                diag.segmentCount = segmentCount
                diag.segmentDiagnostics = segmentDiagList
                diagnostics.sessionError(sessionID: sessionID, error: mapped)
                diagnostics.sessionEnded(sessionID: sessionID, result: diag)
                await MainActor.run { handleError(mapped) }
                return
            }

            let asrMs = Int(Date().timeIntervalSince(asrStart) * 1000)
            totalASRMs += asrMs

            let segDiag = SegmentDiagnostics(
                index: segment.index,
                audioDurationMs: Int(segment.durationSeconds * 1000),
                denoiseMs: denoiseMs,
                asrMs: asrMs,
                charCount: transcriptResult.text.count,
                sealReason: segment.sealReason.rawValue
            )
            segmentDiagList.append(segDiag)
            diagnostics.segmentASRCompleted(sessionID: sessionID, segment: segDiag)

            if !transcriptResult.text.isEmpty {
                transcripts.append(transcriptResult.text)
                accumulatedChars += transcriptResult.text.count
            }

            // 检查累计字符数
            if accumulatedChars > maxChars {
                diag.asrMs = totalASRMs
                diag.denoiseMs = totalDenoiseMs
                diag.totalMs = Int(Date().timeIntervalSince(sessionStart) * 1000)
                diag.segmentCount = segmentCount
                diag.segmentDiagnostics = segmentDiagList
                let tooLongError = TypolessError.transcriptTooLong(charCount: accumulatedChars)
                diag.errorClassification = tooLongError.diagnosticClassification
                diagnostics.sessionError(sessionID: sessionID, error: tooLongError)
                diagnostics.sessionEnded(sessionID: sessionID, result: diag)
                await MainActor.run { handleError(tooLongError) }
                return
            }
        }

        guard await MainActor.run(body: { sessionGeneration }) == generation,
              !Task.isCancelled else { return }

        let combinedTranscript = transcripts.joined()
        diag.asrMs = totalASRMs
        diag.denoiseMs = totalDenoiseMs
        diag.segmentCount = segmentCount
        diag.segmentDiagnostics = segmentDiagList
        diagnostics.asrCompleted(
            sessionID: sessionID,
            text: combinedTranscript,
            durationMs: totalASRMs,
            coldStart: wasColdStart,
            warmupWaitMs: 0
        )

        // 空转写检查
        if combinedTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            diag.totalMs = Int(Date().timeIntervalSince(sessionStart) * 1000)
            diag.errorClassification = TypolessError.cloudASREmptyResponse.diagnosticClassification
            diagnostics.sessionEnded(sessionID: sessionID, result: diag)
            await MainActor.run { handleError(.cloudASREmptyResponse) }
            return
        }

        // LLM 润色
        guard isLLMConfigured else {
            diag.totalMs = Int(Date().timeIntervalSince(sessionStart) * 1000)
            diag.errorClassification = TypolessError.llmConfigurationIncomplete.diagnosticClassification
            diagnostics.sessionError(sessionID: sessionID, error: .llmConfigurationIncomplete)
            diagnostics.sessionEnded(sessionID: sessionID, result: diag)
            await MainActor.run { handleError(.llmConfigurationIncomplete) }
            return
        }

        await MainActor.run { state = .polishing }
        let llmProvider = await MainActor.run {
            LLMProvider(
                baseURL: llmConfig.baseURL,
                apiKey: openAIAPIKey,
                model: llmConfig.model,
                thinkingDisabled: llmConfig.thinkingDisabled,
                dictionaryTerms: terms,
                onThinkingUnsupported: { [self] in
                    try? self.configStore.markThinkingDisabledForCurrentLLM()
                }
            )
        }

        let llmStart = Date()
        let polishResult: PolishResult
        do {
            polishResult = try await llmProvider.polish(text: combinedTranscript, segmentCount: transcripts.count)
        } catch {
            guard await MainActor.run(body: { sessionGeneration }) == generation,
                  !Task.isCancelled else { return }
            let mapped = await MainActor.run { mapError(error) }
            diag.llmMs = Int(Date().timeIntervalSince(llmStart) * 1000)
            diag.totalMs = Int(Date().timeIntervalSince(sessionStart) * 1000)
            diag.errorClassification = mapped.diagnosticClassification
            diagnostics.sessionError(sessionID: sessionID, error: mapped)
            diagnostics.sessionEnded(sessionID: sessionID, result: diag)
            await MainActor.run { handleError(mapped) }
            return
        }

        guard await MainActor.run(body: { sessionGeneration }) == generation,
              !Task.isCancelled else { return }
        let llmMs = Int(Date().timeIntervalSince(llmStart) * 1000)
        diag.llmMs = llmMs
        diagnostics.llmCompleted(
            sessionID: sessionID,
            text: polishResult.text,
            source: polishResult.source.rawValue,
            durationMs: llmMs
        )
        diagnostics.structuredProcessingCompleted(
            sessionID: sessionID,
            mode: polishResult.structured?.mode.rawValue,
            correctionApplied: polishResult.structured?.correctionApplied ?? false,
            parseSuccess: polishResult.structured != nil,
            fallback: polishResult.structured == nil
        )

        // 文本注入（支持翻译模式）
        await MainActor.run { state = .injecting }
        diag.resultSource = polishResult.source.rawValue

        var finalText = polishResult.text

        if processingMode == .translate {
            let translateStart = Date()
            do {
                let translated = try await llmProvider.translate(text: polishResult.text, targetLanguage: translationTarget)
                finalText = translated
                let translateMs = Int(Date().timeIntervalSince(translateStart) * 1000)
                diag.llmMs = (diag.llmMs ?? 0) + translateMs
                diagnostics.llmCompleted(sessionID: sessionID, text: finalText, source: polishResult.source.rawValue, durationMs: translateMs)
            } catch {
                guard await MainActor.run(body: { sessionGeneration }) == generation,
                      !Task.isCancelled else { return }
                let mapped = await MainActor.run { mapError(error) }
                let translateMs = Int(Date().timeIntervalSince(translateStart) * 1000)
                diag.llmMs = (diag.llmMs ?? 0) + translateMs
                diag.totalMs = Int(Date().timeIntervalSince(sessionStart) * 1000)
                diag.errorClassification = mapped.diagnosticClassification
                diagnostics.sessionError(sessionID: sessionID, error: mapped)
                diagnostics.sessionEnded(sessionID: sessionID, result: diag)
                await MainActor.run { handleError(mapped) }
                return
            }
        }

        await MainActor.run { lastResult = SessionResult(text: finalText, source: polishResult.source) }

        let injectionStart = Date()
        do {
            let targetPID = await MainActor.run { targetApplicationPID }
            let targetBundleID = await MainActor.run { targetApplicationBundleID }
            try textInjector.inject(
                text: finalText,
                targetPID: targetPID,
                targetBundleID: targetBundleID
            )
        } catch {
            guard await MainActor.run(body: { sessionGeneration }) == generation else { return }
            let mapped = await MainActor.run { mapError(error) }
            diag.injectionMs = Int(Date().timeIntervalSince(injectionStart) * 1000)
            diag.totalMs = Int(Date().timeIntervalSince(sessionStart) * 1000)
            diag.errorClassification = mapped.diagnosticClassification
            diagnostics.sessionError(sessionID: sessionID, error: mapped)
            diagnostics.sessionEnded(sessionID: sessionID, result: diag)
            await MainActor.run {
                lastInjectionFailureText = finalText
                handleError(mapped)
            }
            return
        }

        guard await MainActor.run(body: { sessionGeneration }) == generation else { return }
        diag.injectionMs = Int(Date().timeIntervalSince(injectionStart) * 1000)
        diag.totalMs = Int(Date().timeIntervalSince(sessionStart) * 1000)

        await MainActor.run {
            lastInjectionFailureText = nil
            state = .done
            diagnostics.sessionEnded(sessionID: sessionID, result: diag)
            onFeedbackEvent?(.processingFinished)
            scheduleResetToIdle()
        }
    }

    // MARK: - Segmenter Cleanup

    private func cleanupSegmenterState() {
        segmenter.onSegmentSealed = nil
        segmentContinuation?.finish()
        segmentContinuation = nil
        segmentStream = nil
        segmenter.reset()
    }

    // MARK: - Error Handling

    private func handleError(_ error: TypolessError) {
        currentError = error
        state = .error
        onFeedbackEvent?(.processingFailed(error.hudFailureReason))
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
        if let recorderError = error as? AudioRecorderError {
            return .audioRecordingUnavailable(detail: recorderError.localizedDescription)
        }
        return .textInjectionFailure(detail: error.localizedDescription)
    }

    private func scheduleResetToIdle() {
        resetToIdleTask?.cancel()
        resetToIdleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self else { return }
            guard self.state == .error || self.state == .cancelled || self.state == .done else { return }
            self.state = .idle
            self.targetApplicationPID = nil
            self.targetApplicationBundleID = nil
            self.resetToIdleTask = nil
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
}
