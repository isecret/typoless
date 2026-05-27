import AVFoundation
import Foundation
import os

@MainActor
protocol FeedbackSoundPlaying: AnyObject {
    func playStart()
    func playStop()
    func playStartAfterOutputStabilizes(
        maxWaitMs: Int,
        minimumWaitMs: Int,
        pollIntervalMs: Int,
        retryDelayMs: Int
    ) async
    func setSilentKeepAliveEnabled(_ enabled: Bool)
}

extension FeedbackSoundPlaying {
    func playStartAfterOutputStabilizes(
        maxWaitMs: Int = 1_200,
        minimumWaitMs: Int = 600,
        pollIntervalMs: Int = 100,
        retryDelayMs: Int = 150
    ) async {
        guard !Task.isCancelled else { return }
        playStart()
    }

    func setSilentKeepAliveEnabled(_ enabled: Bool) {}
}

/// 反馈音效播放器，基于 AVAudioEngine 实现音效播放。
///
/// 引擎在每次播放时按需启动，自动适配当前硬件采样率。
/// 开始音效会等待输出格式稳定，避免录音触发的硬件重配置吞掉提示音。
@MainActor
final class FeedbackSoundPlayer: FeedbackSoundPlaying {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let audioFormat: AVAudioFormat
    private let silentKeepAlive = SilentOutputKeepAlive()

    private var startBuffer: AVAudioPCMBuffer?
    private var stopBuffer: AVAudioPCMBuffer?
    private var configurationObserver: NotificationObserver?
    private var configurationChangeCount: UInt64 = 0
    private var needsReconnect = false

    private static let logger = Logger(subsystem: "com.isecret.typoless", category: "FeedbackSound")

    init() {
        audioFormat = FeedbackSoundDesigner.makePlaybackFormat()

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: audioFormat)

        startBuffer = FeedbackSoundDesigner.makeBuffer(for: .start, format: audioFormat)
        stopBuffer = FeedbackSoundDesigner.makeBuffer(for: .stop, format: audioFormat)

        configurationObserver = NotificationObserver(NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleEngineConfigurationChange()
            }
        })

        Self.logger.info("init | startBuffer=\(self.startBuffer != nil) stopBuffer=\(self.stopBuffer != nil)")
    }

    func playStart() {
        play(startBuffer, label: "start")
    }

    func playStop() {
        play(stopBuffer, label: "stop")
    }

    func setSilentKeepAliveEnabled(_ enabled: Bool) {
        Task { [silentKeepAlive] in
            await silentKeepAlive.setEnabled(enabled)
        }
    }

    func playStartAfterOutputStabilizes(
        maxWaitMs: Int = 1_200,
        minimumWaitMs: Int = 600,
        pollIntervalMs: Int = 100,
        retryDelayMs: Int = 150
    ) async {
        await waitForStableOutputFormat(
            maxWaitMs: maxWaitMs,
            minimumWaitMs: minimumWaitMs,
            pollIntervalMs: pollIntervalMs
        )
        guard !Task.isCancelled else { return }

        let changeCountBeforePlayback = configurationChangeCount
        let didPlay = play(startBuffer, label: "start")

        try? await Task.sleep(nanoseconds: UInt64(max(0, retryDelayMs)) * 1_000_000)
        guard !Task.isCancelled else { return }

        if !didPlay || configurationChangeCount != changeCountBeforePlayback || !playerNode.isPlaying {
            Self.logger.info(
                "play(start) retry | initialPlayed=\(didPlay) configChanged=\(self.configurationChangeCount != changeCountBeforePlayback) node.isPlaying=\(self.playerNode.isPlaying)"
            )
            _ = play(startBuffer, label: "start_retry")
        }
    }

    // MARK: - Engine Lifecycle

    @discardableResult
    private func startEngineIfNeeded() -> Bool {
        if needsReconnect {
            playerNode.stop()
            engine.disconnectNodeOutput(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: audioFormat)
            needsReconnect = false
        }

        guard !engine.isRunning else { return true }

        engine.prepare()
        do {
            try engine.start()
            let fmt = engine.outputNode.outputFormat(forBus: 0)
            Self.logger.info(
                "engine started ✓ | sampleRate=\(fmt.sampleRate, format: .fixed(precision: 0)) channels=\(fmt.channelCount)"
            )
            return true
        } catch {
            Self.logger.error("engine start FAILED: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    private func play(_ buffer: AVAudioPCMBuffer?, label: String) -> Bool {
        guard let buffer else {
            Self.logger.error("play(\(label)) | buffer is nil")
            return false
        }
        guard startEngineIfNeeded(), engine.isRunning else {
            Self.logger.error("play(\(label)) | engine NOT running after start attempt")
            return false
        }
        playerNode.stop()
        playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        playerNode.play()
        Self.logger.info("play(\(label)) | scheduled & playing, node.isPlaying=\(self.playerNode.isPlaying)")
        return playerNode.isPlaying
    }

    private func handleEngineConfigurationChange() {
        configurationChangeCount &+= 1
        needsReconnect = true
        playerNode.stop()
        engine.stop()

        let fmt = currentOutputFormatSnapshot()
        Self.logger.info(
            "engine configuration changed | count=\(self.configurationChangeCount) output=\(fmt.description, privacy: .public)"
        )
    }

    private func waitForStableOutputFormat(
        maxWaitMs: Int,
        minimumWaitMs: Int,
        pollIntervalMs: Int
    ) async {
        let maxWaitMs = max(0, maxWaitMs)
        let minimumWaitMs = min(max(0, minimumWaitMs), maxWaitMs)
        let pollIntervalMs = max(20, pollIntervalMs)
        var waitedMs = 0
        var lastSnapshot = currentOutputFormatSnapshot()
        var consecutiveStablePolls = 0

        Self.logger.info(
            "start cue waiting for stable output | initial=\(lastSnapshot.description, privacy: .public) maxWaitMs=\(maxWaitMs) minimumWaitMs=\(minimumWaitMs)"
        )

        while waitedMs < maxWaitMs, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(pollIntervalMs) * 1_000_000)
            waitedMs += pollIntervalMs

            let nextSnapshot = currentOutputFormatSnapshot()
            if nextSnapshot == lastSnapshot {
                consecutiveStablePolls += 1
            } else {
                Self.logger.info(
                    "output format changed while waiting | from=\(lastSnapshot.description, privacy: .public) to=\(nextSnapshot.description, privacy: .public)"
                )
                consecutiveStablePolls = 0
                lastSnapshot = nextSnapshot
            }

            if waitedMs >= minimumWaitMs, consecutiveStablePolls >= 2 {
                Self.logger.info(
                    "output format stable | waitedMs=\(waitedMs) output=\(nextSnapshot.description, privacy: .public)"
                )
                return
            }
        }

        Self.logger.info(
            "output stabilization finished by timeout/cancel | waitedMs=\(waitedMs) output=\(lastSnapshot.description, privacy: .public)"
        )
    }

    private func currentOutputFormatSnapshot() -> OutputFormatSnapshot {
        let format = engine.outputNode.outputFormat(forBus: 0)
        return OutputFormatSnapshot(
            sampleRate: Int(format.sampleRate.rounded()),
            channelCount: format.channelCount
        )
    }
}

private struct OutputFormatSnapshot: Equatable, CustomStringConvertible {
    let sampleRate: Int
    let channelCount: AVAudioChannelCount

    var description: String {
        "\(sampleRate)Hz/\(channelCount)ch"
    }
}

private actor SilentOutputKeepAlive {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let audioFormat: AVAudioFormat
    private let silentBuffer: AVAudioPCMBuffer?
    private var keepAliveTask: Task<Void, Never>?

    private static let logger = Logger(subsystem: "com.isecret.typoless", category: "FeedbackSound")
    private static let interval: Duration = .seconds(12)

    init() {
        audioFormat = FeedbackSoundDesigner.makePlaybackFormat()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: audioFormat)
        silentBuffer = Self.makeSilentBuffer(format: audioFormat, durationMs: 70)
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            startIfNeeded()
        } else {
            stop()
        }
    }

    private func startIfNeeded() {
        guard keepAliveTask == nil else { return }
        keepAliveTask = Task { [weak self] in
            await self?.runLoop()
        }
        Self.logger.info("silent keep-alive enabled")
    }

    private func stop() {
        keepAliveTask?.cancel()
        keepAliveTask = nil
        playerNode.stop()
        engine.stop()
        Self.logger.info("silent keep-alive disabled")
    }

    private func runLoop() async {
        defer {
            keepAliveTask = nil
            playerNode.stop()
        }

        while !Task.isCancelled {
            playTick()
            do {
                try await Task.sleep(for: Self.interval)
            } catch {
                return
            }
        }
    }

    private func playTick() {
        guard let silentBuffer else {
            Self.logger.error("silent keep-alive skipped | buffer is nil")
            return
        }
        guard startEngineIfNeeded() else { return }

        playerNode.stop()
        playerNode.scheduleBuffer(silentBuffer, at: nil, options: [], completionHandler: nil)
        playerNode.play()
        Self.logger.info("silent keep-alive tick")
    }

    private func startEngineIfNeeded() -> Bool {
        guard !engine.isRunning else { return true }

        engine.prepare()
        do {
            try engine.start()
            Self.logger.info("silent keep-alive engine started")
            return true
        } catch {
            Self.logger.error("silent keep-alive engine start FAILED: \(error.localizedDescription)")
            return false
        }
    }

    private static func makeSilentBuffer(format: AVAudioFormat, durationMs: Double) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(max(1, Int(format.sampleRate * durationMs / 1_000)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        if let channelData = buffer.floatChannelData {
            for channel in 0..<Int(format.channelCount) {
                for frame in 0..<Int(frameCount) {
                    channelData[channel][frame] = 0
                }
            }
        }

        return buffer
    }
}

private final class NotificationObserver: @unchecked Sendable {
    private let token: NSObjectProtocol

    init(_ token: NSObjectProtocol) {
        self.token = token
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}
