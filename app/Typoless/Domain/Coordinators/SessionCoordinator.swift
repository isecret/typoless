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
    private let windowContextService = WindowContextService()
    private let diagnostics = DiagnosticsLogger.shared

    /// SenseVoice 运行时管理器，跨 session 复用
    private let asrRuntimeManager = SenseVoiceRuntimeManager()

    private var processingTask: Task<Void, Never>?
    private var windowContextTask: Task<Void, Never>?
    private var postInjectionLearningTask: Task<Void, Never>?
    private var resetToIdleTask: Task<Void, Never>?
    private var recordingStartTask: Task<Void, Never>?
    private var soundCueTask: Task<Void, Never>?
    private var sessionGeneration: UInt64 = 0
    private var currentSessionID: String = ""
    private var processingMode: TextProcessingMode = .polish

    // 分段相关
    private let segmenter = AudioSegmenter()
    private var segmentStream: AsyncStream<SealedSegment>?
    private var segmentContinuation: AsyncStream<SealedSegment>.Continuation?
    /// 录音时长（毫秒），finishRecording 写入，processSegmentedAudio 读取
    private var recordingDurationMs: Int = 0
    private var capturedWindowContext: WindowContextSnapshot?
    private let ensureMicrophoneAuthorized: @MainActor @Sendable () throws -> Void
    private let ensureAccessibilityAuthorized: @MainActor @Sendable () throws -> Void

    init(
        permissionsManager: PermissionsManager,
        configStore: ConfigStore,
        audioDeviceManager: AudioDeviceManager,
        dictionaryStore: PersonalDictionaryStore? = nil,
        postInjectionLearner: (any PostInjectionDictionaryLearning)? = nil,
        ensureMicrophoneAuthorized: (@MainActor @Sendable () throws -> Void)? = nil,
        ensureAccessibilityAuthorized: (@MainActor @Sendable () throws -> Void)? = nil
    ) {
        self.permissionsManager = permissionsManager
        self.configStore = configStore
        self.audioDeviceManager = audioDeviceManager
        self.dictionaryStore = dictionaryStore
        self.ensureMicrophoneAuthorized = ensureMicrophoneAuthorized
            ?? { try permissionsManager.ensureMicrophoneAuthorized() }
        self.ensureAccessibilityAuthorized = ensureAccessibilityAuthorized
            ?? { try permissionsManager.ensureAccessibilityAuthorized() }
        self.postInjectionLearner = postInjectionLearner ?? PostInjectionDictionaryLearner(
            termEvaluator: LLMProperNounTermEvaluator(
                providerFactory: {
                    guard configStore.isLLMConfigured else { return nil }
                    return LLMProvider(
                        baseURL: configStore.llmConfig.baseURL,
                        apiKey: configStore.openAIAPIKey,
                        model: configStore.llmConfig.model,
                        thinkingDisabled: configStore.llmConfig.thinkingDisabled,
                        onThinkingUnsupported: {
                            try? configStore.markThinkingDisabledForCurrentLLM()
                        }
                    )
                }
            )
        )
    }

    private let dictionaryStore: PersonalDictionaryStore?
    private let postInjectionLearner: any PostInjectionDictionaryLearning

    /// 开始录音
    func startRecording() {
        guard state.allowsRecordingStart else { return }

        if state != .idle {
            recordingStartTask?.cancel()
            recordingStartTask = nil
            resetToIdleTask?.cancel()
            resetToIdleTask = nil
            clearWindowContextCapture()
            cancelPostInjectionLearning()
            state = .idle
            targetApplicationPID = nil
            targetApplicationBundleID = nil
        }

        currentError = nil
        lastResult = nil
        clearWindowContextCapture()
        cancelPostInjectionLearning()
        targetApplicationPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        targetApplicationBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        sessionGeneration &+= 1
        currentSessionID = Self.generateSessionID()
        let selectedPlatform = configStore.asrConfig.selectedPlatform
        let sessionID = currentSessionID
        let targetBundleID = targetApplicationBundleID

        do {
            configStore.refreshLocalModelStatusFromDisk()
            try ensureMicrophoneAuthorized()
            try ensureAccessibilityAuthorized()
            try ResourceValidator.validateDenoiseResources()
            // 录音前检查 ASR 平台可用性
            guard configStore.isASRReady else {
                throw TypolessError.asrPlatformNotReady(detail: configStore.asrNotReadyReason ?? "未知")
            }
            // 本地 SenseVoice 额外校验运行时资源
            if configStore.asrConfig.selectedPlatform == .localSenseVoice {
                try ResourceValidator.validateASRResources()
            }
            state = .recording
            processingMode = .polish
            onFeedbackEvent?(.recordingStarted)

            let generation = sessionGeneration
            beginWindowContextCapture(
                generation: generation,
                sessionID: sessionID,
                targetPID: targetApplicationPID,
                targetBundleID: targetBundleID
            )
            recordingStartTask?.cancel()
            recordingStartTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled, let self else { return }
                await self.beginRecording(
                    generation: generation,
                    sessionID: sessionID,
                    targetBundleID: targetBundleID,
                    selectedPlatform: selectedPlatform
                )
                if !Task.isCancelled, self.sessionGeneration == generation {
                    self.recordingStartTask = nil
                }
            }
        } catch {
            handleError(mapError(error))
        }
    }

    private func beginRecording(
        generation: UInt64,
        sessionID: String,
        targetBundleID: String?,
        selectedPlatform: ASRPlatform
    ) async {
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

            // 配置录音器 PCM chunk 回调并启动录音
            // onPCMChunk 在 startRecording 内部 cleanup 后、startRunning 前设置，保证不被清理
            let captureDevice = audioDeviceManager.captureDeviceForRecording()
            try await audioRecorder.startRecording(
                device: captureDevice,
                onPCMChunk: { [segmenter] chunk in
                    segmenter.appendPCMChunk(chunk)
                }
            )
            guard !Task.isCancelled, generation == sessionGeneration, state == .recording else {
                _ = audioRecorder.stopRecording()
                cleanupSegmenterState()
                return
            }

            diagnostics.sessionStarted(
                sessionID: sessionID,
                targetBundleID: targetBundleID
            )
            diagnostics.log(
                sessionID: sessionID,
                event: "recording_device_selected",
                detail: "name=\(captureDevice?.localizedName ?? "system_default") id=\(captureDevice?.uniqueID ?? "system_default")"
            )

            // 录音器已启动。开始音效由 FeedbackSoundPlayer 等待输出路由稳定后播放，
            // 以适配蓝牙耳机从 A2DP 到 HFP/HSP 的 profile 切换。
            soundCueTask = Task { [weak self] in
                await Task.yield()
                guard !Task.isCancelled, let self, self.state == .recording else { return }
                self.diagnostics.log(sessionID: sessionID, event: "start_sound_cue_requested")
                self.onFeedbackEvent?(.startSoundCue)
            }

            // 本地 SenseVoice 模式下录音开始即后台预热 ASR runtime（不阻塞录音）
            if selectedPlatform == .localSenseVoice {
                asrRuntimeManager.warmup()
            }

            // 在录音开始时快照 ASR 配置（录音期间不变）
            // LLM / processingMode 配置在录音结束后读取，保证 toggleProcessingMode 生效
            let asrConfig = configStore.asrConfig

            // 立即启动处理任务，for await 循环会实时消费分段并提前 ASR
            diagnostics.log(sessionID: sessionID, event: "processing_task_started", detail: "concurrent ASR enabled")
            processingTask = Task { [weak self] in
                await self?.processSegmentedAudio(
                    generation: generation,
                    sessionID: sessionID,
                    asrConfig: asrConfig,
                    selectedPlatform: selectedPlatform
                )
                self?.processingTask = nil
            }
        } catch {
            guard !Task.isCancelled, generation == sessionGeneration else { return }
            handleError(mapError(error))
        }
    }

    /// 结束录音并开始处理链路
    func finishRecording() {
        guard state == .recording else { return }

        recordingStartTask?.cancel()
        recordingStartTask = nil
        soundCueTask?.cancel()
        soundCueTask = nil

        let recordingResult = audioRecorder.stopRecording()
        let audioData = recordingResult.data
        lastRecordedAudio = audioData
        onFeedbackEvent?(.recordingStopped)

        // 短录音静默取消（<500ms）：先取消处理任务，再清理流
        if recordingResult.isShortRecording {
            diagnostics.shortRecordingCancelled(
                sessionID: currentSessionID,
                durationMs: recordingResult.durationMs
            )
            sessionGeneration &+= 1
            processingTask?.cancel()
            processingTask = nil
            lastRecordedAudio = nil
            clearWindowContextCapture()
            cancelPostInjectionLearning()
            targetApplicationPID = nil
            targetApplicationBundleID = nil
            cleanupSegmenterState()
            state = .idle
            return
        }

        guard !audioData.isEmpty else {
            sessionGeneration &+= 1
            processingTask?.cancel()
            processingTask = nil
            clearWindowContextCapture()
            cancelPostInjectionLearning()
            cleanupSegmenterState()
            handleError(.asrEmptyAudio)
            return
        }

        // 记录录音时长供处理任务读取
        recordingDurationMs = recordingResult.durationMs

        // 通知分段器结束，触发最终分段，关闭流
        segmenter.finalize()
        segmentContinuation?.finish()

        state = .transcribing
        diagnostics.log(sessionID: currentSessionID, event: "recording_finished", detail: "duration=\(recordingResult.durationMs)ms")
    }

    /// 取消当前任务
    func cancel() {
        switch state {
        case .recording:
            recordingStartTask?.cancel()
            recordingStartTask = nil
            soundCueTask?.cancel()
            soundCueTask = nil
            sessionGeneration &+= 1
            processingTask?.cancel()
            processingTask = nil
            _ = audioRecorder.stopRecording()
            clearWindowContextCapture()
            cancelPostInjectionLearning()
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
            clearWindowContextCapture()
            cancelPostInjectionLearning()
            cleanupSegmenterState()
            // 取消期间 runtime 可能仍在推理，排队销毁旧 recognizer，防止旧状态污染后续 session
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
        asrConfig: ASRConfig,
        selectedPlatform: ASRPlatform
    ) async {
        let sessionStart = Date()
        var diag = SessionDiagnostics()
        diag.targetBundleID = await MainActor.run { targetApplicationBundleID }

        let wasColdStart = !asrRuntimeManager.isWarm

        // 本地 SenseVoice：等待预热完成
        if selectedPlatform == .localSenseVoice {
            do {
                try await asrRuntimeManager.awaitWarmupIfNeeded()
            } catch {
                diagnostics.log(sessionID: sessionID, event: "warmup_failed", detail: error.localizedDescription)
            }
        }

        // 构建 ASR Provider
        let asrProviderFactory = ASRProviderFactory(runtimeManager: asrRuntimeManager)
        let asrProvider = asrProviderFactory.makeProvider(for: asrConfig)

        guard let stream = await MainActor.run(body: { segmentStream }) else { return }

        // 串行处理分段（录音期间实时消费，提前 ASR）
        var transcripts: [String] = []
        var totalASRMs: Int = 0
        var totalDenoiseMs: Int = 0
        var accumulatedChars: Int = 0
        var segmentDiagList: [SegmentDiagnostics] = []
        var segmentCount = 0
        let maxChars = 8000

        diagnostics.log(sessionID: sessionID, event: "asr_loop_started", detail: "waiting for segments")

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

            // ASR 识别（动态超时：按 AGENTS.md 规范 min(90s, max(15s, duration * 1.3 + 10s))）
            let dynamicTimeout = min(90.0, max(15.0, segment.durationSeconds * 1.3 + 10.0))
            diagnostics.log(sessionID: sessionID, event: "segment_asr_started", detail: "index=\(segment.index) duration=\(Int(segment.durationSeconds * 1000))ms timeout=\(Int(dynamicTimeout))s")
            let asrStart = Date()
            let transcriptResult: TranscriptResult
            do {
                transcriptResult = try await asrProvider.recognize(audioData: processedAudio, timeout: dynamicTimeout)
                if selectedPlatform == .localSenseVoice {
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
                // ASR 错误可能发生在录音期间，需要停止录音并清理
                await MainActor.run {
                    if state == .recording {
                        soundCueTask?.cancel()
                        soundCueTask = nil
                        _ = audioRecorder.stopRecording()
                        cleanupSegmenterState()
                    }
                    handleError(mapped)
                }
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
                diagnostics.log(sessionID: sessionID, event: "segment_transcript", detail: "index=\(segment.index) chars=\(transcriptResult.text.count) accumulated=\(accumulatedChars)")
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
                await MainActor.run {
                    if state == .recording {
                        soundCueTask?.cancel()
                        soundCueTask = nil
                        _ = audioRecorder.stopRecording()
                        cleanupSegmenterState()
                    }
                    handleError(tooLongError)
                }
                return
            }
        }

        // --- 流已结束（录音已停止，所有分段已处理）---

        guard await MainActor.run(body: { sessionGeneration }) == generation,
              !Task.isCancelled else { return }

        // 读取录音结束后才确定的配置
        let (
            recordingMs,
            currentProcessingMode,
            llmConfig,
            openAIAPIKey,
            isLLMConfigured,
            terms,
            translationTarget,
            windowContext
        ) = await MainActor.run {
            (
                recordingDurationMs,
                processingMode,
                configStore.llmConfig,
                configStore.openAIAPIKey,
                configStore.isLLMConfigured,
                dictionaryStore?.termsForPrompt() ?? [],
                configStore.generalConfig.translationTargetLanguage,
                capturedWindowContext
            )
        }

        diag.recordingMs = recordingMs

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
            let emptyError: TypolessError = segmentCount == 0
                ? .asrEmptyAudio
                : .asrEmptyTranscript
            diag.errorClassification = emptyError.diagnosticClassification
            diagnostics.sessionEnded(sessionID: sessionID, result: diag)
            await MainActor.run { handleError(emptyError) }
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
            polishResult = try await llmProvider.polish(
                text: combinedTranscript,
                segmentCount: transcripts.count,
                context: windowContext
            )
        } catch {
            guard await MainActor.run(body: { sessionGeneration }) == generation,
                  !Task.isCancelled else { return }
            let mapped = await MainActor.run { mapError(error) }
            diag.llmMs = Int(Date().timeIntervalSince(llmStart) * 1000)
            diag.totalMs = Int(Date().timeIntervalSince(sessionStart) * 1000)
            diag.errorClassification = mapped.diagnosticClassification
            diagnostics.sessionError(sessionID: sessionID, error: mapped)
            diagnostics.sessionEnded(sessionID: sessionID, result: diag)
            await MainActor.run {
                clearWindowContextCapture()
                handleError(mapped)
            }
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

        if currentProcessingMode == .translate {
            let translateStart = Date()
            do {
                let translated = try await llmProvider.translate(
                    text: polishResult.text,
                    targetLanguage: translationTarget,
                    context: windowContext
                )
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
                await MainActor.run {
                    clearWindowContextCapture()
                    handleError(mapped)
                }
                return
            }
        }

        await MainActor.run { lastResult = SessionResult(text: finalText, source: polishResult.source) }

        let injectionStart = Date()
        do {
            let injectionResult = try await MainActor.run {
                try textInjector.inject(
                    text: finalText,
                    targetPID: targetApplicationPID,
                    targetBundleID: targetApplicationBundleID
                )
            }
            diagnostics.injectionCompleted(
                sessionID: sessionID,
                path: injectionResult.path,
                breakdown: injectionResult.breakdown
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
                clearWindowContextCapture()
                handleError(mapped)
            }
            return
        }

        guard await MainActor.run(body: { sessionGeneration }) == generation else { return }
        diag.injectionMs = Int(Date().timeIntervalSince(injectionStart) * 1000)
        diag.totalMs = Int(Date().timeIntervalSince(sessionStart) * 1000)

        await MainActor.run {
            lastInjectionFailureText = nil
            clearWindowContextCapture()
            state = .done
            diagnostics.sessionEnded(sessionID: sessionID, result: diag)
            onFeedbackEvent?(.processingFinished)
            beginPostInjectionLearningIfNeeded(
                generation: generation,
                mode: currentProcessingMode,
                sessionID: sessionID,
                targetPID: targetApplicationPID,
                targetBundleID: targetApplicationBundleID
            )
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
        recordingStartTask?.cancel()
        recordingStartTask = nil
        soundCueTask?.cancel()
        soundCueTask = nil
        clearWindowContextCapture()
        cancelPostInjectionLearning()
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

    private func beginWindowContextCapture(
        generation: UInt64,
        sessionID: String,
        targetPID: pid_t?,
        targetBundleID: String?
    ) {
        windowContextTask?.cancel()
        capturedWindowContext = nil

        windowContextTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.windowContextService.captureContextResult(
                targetPID: targetPID,
                targetBundleID: targetBundleID
            )
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard self.sessionGeneration == generation else { return }
                self.capturedWindowContext = result.snapshot
                self.windowContextTask = nil

                switch result.event {
                case .captured, .redacted:
                    if let rawCandidate = result.rawCandidate {
                        self.diagnostics.windowContextCaptured(
                            sessionID: sessionID,
                            event: result.event,
                            rawCandidate: rawCandidate
                        )
                    }
                    if let snapshot = result.snapshot {
                        let hasBodyText = snapshot.selectedText != nil
                            || snapshot.surroundingTextBefore != nil
                            || snapshot.surroundingTextAfter != nil
                        self.diagnostics.log(
                            sessionID: sessionID,
                            event: result.event.rawValue,
                            detail: "surface=\(snapshot.surfaceKind.rawValue) body=\(hasBodyText) labels=\(snapshot.nearbyLabels.count)"
                        )
                    } else {
                        self.diagnostics.log(sessionID: sessionID, event: result.event.rawValue)
                    }
                case .unavailable, .captureFailed, .timeout:
                    self.diagnostics.log(sessionID: sessionID, event: result.event.rawValue)
                }
            }
        }
    }

    private func clearWindowContextCapture() {
        windowContextTask?.cancel()
        windowContextTask = nil
        capturedWindowContext = nil
    }

    func beginPostInjectionLearningIfNeeded(
        generation: UInt64,
        mode: TextProcessingMode,
        sessionID: String,
        targetPID: pid_t?,
        targetBundleID: String?
    ) {
        cancelPostInjectionLearning()
        guard mode == .polish else { return }
        guard let dictionaryStore else { return }

        postInjectionLearningTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await postInjectionLearner.observe(
                targetPID: targetPID,
                targetBundleID: targetBundleID,
                windowContext: self.capturedWindowContext,
                store: dictionaryStore,
                shouldContinue: { [weak self] in
                    guard let self else { return false }
                    return self.sessionGeneration == generation
                },
                onDecision: { [weak self] decision in
                    guard let self, self.sessionGeneration == generation else { return }
                    switch decision {
                    case .learned(let term):
                        self.diagnostics.log(
                            sessionID: sessionID,
                            event: "dictionary_term_learned",
                            detail: "chars=\(term.count)"
                        )
                        self.onFeedbackEvent?(.dictionaryTermLearned(term))
                    case .rejected(let term):
                        self.diagnostics.log(
                            sessionID: sessionID,
                            event: "dictionary_term_rejected",
                            detail: "chars=\(term.count)"
                        )
                    case .failed(let term, let reason):
                        self.diagnostics.log(
                            sessionID: sessionID,
                            event: "dictionary_term_learning_failed",
                            detail: "chars=\(term.count) reason=\(reason)"
                        )
                    }
                }
            )

            if self.sessionGeneration == generation {
                self.postInjectionLearningTask = nil
            }
        }
    }

    private func cancelPostInjectionLearning() {
        postInjectionLearningTask?.cancel()
        postInjectionLearningTask = nil
    }
}

// MARK: - Session Result

struct SessionResult: Sendable {
    let text: String
    let source: PolishResult.Source
}
