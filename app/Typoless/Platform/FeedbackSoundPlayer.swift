import AVFoundation
import Foundation
import os

@MainActor
protocol FeedbackSoundPlaying: AnyObject {
    func playStart()
    func playStop()
}

/// 反馈音效播放器，基于 AVAudioEngine 实现音效播放。
///
/// 引擎在每次播放时按需启动，自动适配当前硬件采样率。
/// 播放时机由 SessionCoordinator 控制：在 AVAudioRecorder 启动（触发硬件重配置）
/// 之后延迟调用，确保引擎在稳定的硬件配置上启动。
@MainActor
final class FeedbackSoundPlayer: FeedbackSoundPlaying {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let audioFormat: AVAudioFormat

    private var startBuffer: AVAudioPCMBuffer?
    private var stopBuffer: AVAudioPCMBuffer?

    private static let logger = Logger(subsystem: "com.isecret.typoless", category: "FeedbackSound")

    init() {
        audioFormat = FeedbackSoundDesigner.makePlaybackFormat()

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: audioFormat)

        startBuffer = FeedbackSoundDesigner.makeBuffer(for: .start, format: audioFormat)
        stopBuffer = FeedbackSoundDesigner.makeBuffer(for: .stop, format: audioFormat)

        Self.logger.info("init | startBuffer=\(self.startBuffer != nil) stopBuffer=\(self.stopBuffer != nil)")
    }

    func playStart() {
        play(startBuffer, label: "start")
    }

    func playStop() {
        play(stopBuffer, label: "stop")
    }

    // MARK: - Engine Lifecycle

    @discardableResult
    private func startEngineIfNeeded() -> Bool {
        guard !engine.isRunning else { return false }
        engine.connect(playerNode, to: engine.mainMixerNode, format: audioFormat)
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

    private func play(_ buffer: AVAudioPCMBuffer?, label: String) {
        guard let buffer else {
            Self.logger.error("play(\(label)) | buffer is nil")
            return
        }
        startEngineIfNeeded()
        guard engine.isRunning else {
            Self.logger.error("play(\(label)) | engine NOT running after start attempt")
            return
        }
        playerNode.stop()
        playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        playerNode.play()
        Self.logger.info("play(\(label)) | scheduled & playing, node.isPlaying=\(self.playerNode.isPlaying)")
    }
}
