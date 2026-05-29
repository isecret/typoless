import AppKit
import os
import SwiftUI

/// HUD 反馈控制器，统一驱动 HUD 窗口、状态转换、声波动画和音效播放
@MainActor
@Observable
final class HUDFeedbackController {
    private static let logger = Logger(subsystem: "com.isecret.typoless", category: "HUDFeedback")
    private static let learnedTermDisplayLimit = 4
    static let defaultLearnedTermNoticeDismissSeconds = 1.8

    // MARK: - Observable State (HUDContentView 读取)

    private(set) var hudState: HUDState = .hidden
    private(set) var modeCueLabel: String?
    private(set) var barHeights: [CGFloat] = Array(repeating: HUDLayout.resetBarHeight, count: 7)
    private(set) var isHUDPresented = false

    // MARK: - Callbacks (由 AppCoordinator 注入)

    var onCancelRecording: (() -> Void)?
    var onConfirmRecording: (() -> Void)?
    var onToggleProcessingMode: (() -> Void)?
    /// 返回 0-1 归一化电平的闭包，录音期间由 SessionCoordinator 提供
    var audioLevelProvider: (() -> Float)?
    /// 返回当前是否启用交互音效的闭包，由 AppCoordinator 提供
    var isInteractionSoundEnabled: (() -> Bool)?

    // MARK: - Private

    private let soundPlayer: FeedbackSoundPlaying
    private let modeCueDuration: Duration
    private let learnedTermNoticeDismissSeconds: Double
    private var hudWindow: HUDWindow?
    private var hostingView: NSHostingView<HUDContentView>?
    private var dismissTask: Task<Void, Never>?
    private var modeCueTask: Task<Void, Never>?
    private var levelPollingTask: Task<Void, Never>?
    private var startSoundPlaybackTask: Task<Void, Never>?
    private var escEventTap: CFMachPort?
    private var escRunLoopSource: CFRunLoopSource?
    private var presentationGeneration: UInt64 = 0
    private var waveformEnvelope: CGFloat = 0
    private var waveformEnergy: CGFloat = 0
    private var waveformPhase: CGFloat = 0

    private static let barsCount = 7
    private static let activeWaveformProfile: [CGFloat] = [0.10, 0.42, 0.62, 0.88, 0.62, 0.42, 0.10]
    private static let activeWaveformPeakBias: [CGFloat] = [0, 0, 0.02, 0.14, 0.02, 0, 0]

    init(
        soundPlayer: FeedbackSoundPlaying = FeedbackSoundPlayer(),
        modeCueDuration: Duration = .milliseconds(650),
        learnedTermNoticeDismissSeconds: Double = HUDFeedbackController.defaultLearnedTermNoticeDismissSeconds
    ) {
        self.soundPlayer = soundPlayer
        self.modeCueDuration = modeCueDuration
        self.learnedTermNoticeDismissSeconds = learnedTermNoticeDismissSeconds
    }

    // MARK: - Public Event Handler

    func setInteractionSoundKeepAliveEnabled(_ enabled: Bool) {
        soundPlayer.setSilentKeepAliveEnabled(enabled)
    }

    /// 处理来自 SessionCoordinator 的反馈事件
    func handleEvent(_ event: SessionFeedbackEvent) {
        Self.logger.info("handleEvent | \(String(describing: event))")
        dismissTask?.cancel()
        dismissTask = nil
        presentationGeneration &+= 1

        switch event {
        case .recordingStarted:
            cancelPendingStartSound()
            clearModeCue()
            hudState = .recording
            showHUD()
            startLevelPolling()
            startEscMonitor()

        case .startSoundCue:
            playStartSoundWhenReady()

        case .recordingStopped:
            cancelPendingStartSound()
            clearModeCue()
            if shouldPlayInteractionSound {
                soundPlayer.playStop()
            }
            stopLevelPolling()
            stopEscMonitor()
            resetBars()
            hudState = .processing
            updateMouseInteraction()

        case .modeSwitched(let mode):
            let label = (mode == .translate) ? "TRANSLATE" : "DICTATE"
            guard hudState == .recording else { return }
            modeCueLabel = label
            modeCueTask?.cancel()
            let duration = modeCueDuration
            modeCueTask = Task { [weak self] in
                try? await Task.sleep(for: duration)
                guard let self else { return }
                guard self.hudState == .recording, self.modeCueLabel == label else { return }
                self.modeCueLabel = nil
                self.modeCueTask = nil
            }

        case .processingFinished:
            cancelPendingStartSound()
            clearModeCue()
            stopLevelPolling()
            stopEscMonitor()
            resetBars()
            dismissHUD()

        case .dictionaryTermLearned(let term):
            clearModeCue()
            stopLevelPolling()
            stopEscMonitor()
            resetBars()
            hudState = .notice(Self.learnedTermNoticeText(term))
            if isHUDPresented {
                updateMouseInteraction()
            } else {
                showHUD()
            }
            scheduleDismiss(after: learnedTermNoticeDismissSeconds)

        case .processingFailed(let reason):
            cancelPendingStartSound()
            clearModeCue()
            stopLevelPolling()
            stopEscMonitor()
            resetBars()
            hudState = .failure(reason)
            if isHUDPresented {
                updateMouseInteraction()
            } else {
                showHUD()
            }
            scheduleDismiss(after: 1.2)

        case .processingCancelled:
            cancelPendingStartSound()
            clearModeCue()
            stopLevelPolling()
            stopEscMonitor()
            resetBars()
            dismissHUD()
        }
    }

    private func playStartSoundWhenReady() {
        cancelPendingStartSound()
        guard shouldPlayInteractionSound else { return }

        startSoundPlaybackTask = Task { [weak self] in
            guard let self else { return }
            await self.soundPlayer.playStartAfterOutputStabilizes(
                maxWaitMs: 2_200,
                minimumWaitMs: 600,
                pollIntervalMs: 100,
                retryDelayMs: 200
            )
            if !Task.isCancelled {
                self.startSoundPlaybackTask = nil
            }
        }
    }

    private func cancelPendingStartSound() {
        startSoundPlaybackTask?.cancel()
        startSoundPlaybackTask = nil
    }

    // MARK: - Audio Level Polling

    private func startLevelPolling() {
        levelPollingTask?.cancel()
        levelPollingTask = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    guard let self else { return }
                    let level = self.audioLevelProvider?() ?? 0
                    self.updateWaveform(level: level)
                    try await Task.sleep(for: .milliseconds(16))
                }
            } catch is CancellationError {
                // 正常取消退出
            } catch {}
        }
    }

    private func stopLevelPolling() {
        levelPollingTask?.cancel()
        levelPollingTask = nil
    }

    private var shouldPlayInteractionSound: Bool {
        isInteractionSoundEnabled?() ?? true
    }

    // MARK: - ESC Key Monitor

    /// 录音阶段监听 ESC 键以取消录音，并吞掉该按键避免穿透到前台应用
    private func startEscMonitor() {
        stopEscMonitor()

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard
                type == .keyDown,
                let userInfo
            else {
                return Unmanaged.passRetained(event)
            }

            let controller = Unmanaged<HUDFeedbackController>
                .fromOpaque(userInfo)
                .takeUnretainedValue()

            let keycode = event.getIntegerValueField(.keyboardEventKeycode)

            // ESC
            if keycode == 53 {
                Task { @MainActor in
                    guard controller.hudState == .recording else { return }
                    controller.onCancelRecording?()
                }
                return nil
            }

            // Shift+Tab
            if keycode == 48 && event.flags.contains(.maskShift) {
                Task { @MainActor in
                    guard controller.hudState == .recording else { return }
                    controller.onToggleProcessingMode?()
                }
                return nil
            }

            return Unmanaged.passRetained(event)
        }

        let ref = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: ref
        ) else {
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        escEventTap = tap
        escRunLoopSource = source
    }

    private func stopEscMonitor() {
        if let source = escRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            escRunLoopSource = nil
        }

        if let tap = escEventTap {
            CFMachPortInvalidate(tap)
            escEventTap = nil
        }
    }

    /// 根据音频电平计算声波条高度：低幅待机 + 软触发的有声峰值
    private func updateWaveform(level: Float) {
        let clampedLevel = min(max(CGFloat(level), 0), 1)
        let maxH = HUDLayout.waveformMaxHeight
        let minH = HUDLayout.waveformMinHeight
        let presenceTarget = Self.smoothStep(edge0: 0.08, edge1: 0.17, value: clampedLevel)
        let energyTarget = Self.smoothStep(edge0: 0.08, edge1: 0.52, value: clampedLevel)

        let presenceRising: CGFloat = 0.42
        let presenceFalling: CGFloat = 0.16
        let presenceSmoothing = presenceTarget > waveformEnvelope ? presenceRising : presenceFalling
        waveformEnvelope += (presenceTarget - waveformEnvelope) * presenceSmoothing

        let energyRising: CGFloat = 0.24
        let energyFalling: CGFloat = 0.18
        let energySmoothing = energyTarget > waveformEnergy ? energyRising : energyFalling
        waveformEnergy += (energyTarget - waveformEnergy) * energySmoothing

        waveformPhase += 0.16 + waveformEnvelope * 0.12 + waveformEnergy * 0.08

        for i in 0..<Self.barsCount {
            let offset = CGFloat(i) * 0.68
            let pulse = (sin(waveformPhase + offset) + 1) * 0.5
            let sway = (sin(waveformPhase * 0.56 - offset * 0.9) + 1) * 0.5

            let profile = Self.activeWaveformProfile[i]
            let idleShape = 0.08 + profile * 0.03 + pulse * 0.025 + sway * 0.02

            let activeFloor = 0.2 + profile * 0.48
            let activeReach = 0.16 + profile * (0.14 + waveformEnergy * 0.22)
            let motion = 0.76 + pulse * 0.18 + sway * 0.1
            let peakBias = Self.activeWaveformPeakBias[i] * (0.75 + waveformEnergy * 0.25)
            let activeShape = min(1, activeFloor + activeReach * motion + peakBias)

            let normalizedHeight = idleShape + (activeShape - idleShape) * waveformEnvelope
            barHeights[i] = minH + normalizedHeight * (maxH - minH)
        }
    }

    private func resetBars() {
        waveformEnvelope = 0
        waveformEnergy = 0
        waveformPhase = 0
        barHeights = Array(repeating: HUDLayout.resetBarHeight, count: Self.barsCount)
    }

    private static func smoothStep(edge0: CGFloat, edge1: CGFloat, value: CGFloat) -> CGFloat {
        guard edge0 != edge1 else { return value >= edge1 ? 1 : 0 }
        let t = min(max((value - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private func clearModeCue() {
        modeCueTask?.cancel()
        modeCueTask = nil
        modeCueLabel = nil
    }

    // MARK: - Window Management

    private func showHUD() {
        ensureWindow()
        hudWindow?.positionOnActiveScreen()
        updateMouseInteraction()
        hudWindow?.alphaValue = 0
        hudWindow?.orderFrontRegardless()
        isHUDPresented = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            self.hudWindow?.animator().alphaValue = 1
        }
    }

    private func dismissHUD() {
        clearModeCue()
        stopLevelPolling()
        stopEscMonitor()
        guard isHUDPresented else {
            hudState = .hidden
            return
        }
        let gen = presentationGeneration
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            self.hudWindow?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.presentationGeneration == gen else { return }
                self.hudWindow?.orderOut(nil)
                self.hudWindow?.ignoresMouseEvents = true
                self.hudState = .hidden
                self.isHUDPresented = false
            }
        })
    }

    private func scheduleDismiss(after seconds: Double) {
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismissHUD()
        }
    }

    /// 录音态需要响应鼠标（X/✓ 按钮），其他态不拦截鼠标事件
    private func updateMouseInteraction() {
        hudWindow?.ignoresMouseEvents = (hudState != .recording)
    }

    private func ensureWindow() {
        guard hudWindow == nil else { return }

        let contentView = HUDContentView(
            controller: self,
            onCancel: { [weak self] in self?.onCancelRecording?() },
            onConfirm: { [weak self] in self?.onConfirmRecording?() }
        )
        let hosting = NSHostingView(rootView: contentView)
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: 200, height: 44))

        hostingView = hosting
        hudWindow = HUDWindow(contentView: hosting)
    }

    private static func learnedTermNoticeText(_ term: String) -> String {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "-" }

        let glyphs = Array(trimmed)
        let displayTerm: String
        if glyphs.count <= learnedTermDisplayLimit {
            displayTerm = String(glyphs)
        } else {
            displayTerm = String(glyphs.prefix(learnedTermDisplayLimit)) + "…"
        }
        return displayTerm
    }
}
