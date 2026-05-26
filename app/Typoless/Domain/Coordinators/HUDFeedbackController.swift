import AppKit
import os
import SwiftUI

/// HUD 反馈控制器，统一驱动 HUD 窗口、状态转换、声波动画和音效播放
@MainActor
@Observable
final class HUDFeedbackController {
    private static let logger = Logger(subsystem: "com.isecret.typoless", category: "HUDFeedback")

    // MARK: - Observable State (HUDContentView 读取)

    private(set) var hudState: HUDState = .hidden
    private(set) var modeCueLabel: String?
    private(set) var barHeights: [CGFloat] = Array(repeating: 1, count: 7)
    private(set) var barOpacities: [Double] = Array(repeating: 0.28, count: 7)
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
    private var waveformPhase: CGFloat = 0

    private static let barsCount = 7

    init(
        soundPlayer: FeedbackSoundPlaying = FeedbackSoundPlayer(),
        modeCueDuration: Duration = .milliseconds(650)
    ) {
        self.soundPlayer = soundPlayer
        self.modeCueDuration = modeCueDuration
    }

    // MARK: - Public Event Handler

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
            clearModeCue()
            hudState = .success
            scheduleDismiss(after: 0.8)

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
            hudState = .cancelled
            updateMouseInteraction()
            scheduleDismiss(after: 0.8)
        }
    }

    private func playStartSoundWhenReady() {
        cancelPendingStartSound()
        guard shouldPlayInteractionSound else { return }

        startSoundPlaybackTask = Task { [weak self] in
            guard let self else { return }
            await self.soundPlayer.playStartAfterOutputStabilizes(
                maxWaitMs: 1_200,
                minimumWaitMs: 600,
                pollIntervalMs: 100,
                retryDelayMs: 150
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

    /// 根据音频电平计算声波条高度，复刻原型 JS 算法
    private func updateWaveform(level: Float) {
        let rawTarget = CGFloat(level)
        let count = Self.barsCount
        let maxH: CGFloat = 12.6
        let minH: CGFloat = 1.2
        let center = CGFloat(count - 1) / 2

        // 使用包络平滑替代逐帧随机跳变，让整体起伏更连续自然。
        let risingSmoothing: CGFloat = 0.34
        let fallingSmoothing: CGFloat = 0.2
        let smoothing = rawTarget > waveformEnvelope ? risingSmoothing : fallingSmoothing
        waveformEnvelope += (rawTarget - waveformEnvelope) * smoothing
        waveformPhase += 0.28 + waveformEnvelope * 0.18

        for i in 0..<count {
            let centerWeight = 1 - abs(CGFloat(i) - center) / center
            let offset = CGFloat(i) * 0.72
            let pulse = (sin(waveformPhase + offset) + 1) * 0.5
            let modulation = 0.94 + pulse * 0.16
            let floor = 0.22 + centerWeight * 0.06
            let eased = floor + waveformEnvelope * (0.5 + centerWeight * 0.66) * modulation
            barHeights[i] = minH + eased * (maxH - minH)
            barOpacities[i] = 0.28 + min(0.72, Double(eased))
        }
    }

    private func resetBars() {
        waveformEnvelope = 0
        waveformPhase = 0
        barHeights = Array(repeating: 1, count: Self.barsCount)
        barOpacities = Array(repeating: 0.28, count: Self.barsCount)
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
}
