import AVFoundation
import Foundation
import os

/// 反馈音效播放器，基于 AVAudioEngine 实现音效播放。
///
/// 引擎在每次播放时按需启动，自动适配当前硬件采样率。
/// 播放时机由 SessionCoordinator 控制：在 AVAudioRecorder 启动（触发硬件重配置）
/// 之后延迟调用，确保引擎在稳定的硬件配置上启动。
@MainActor
final class FeedbackSoundPlayer {
    private struct ToneSegment {
        let frequency: Double
        let gain: Double
        let durationMs: Int
    }

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let audioFormat: AVAudioFormat

    private var startBuffer: AVAudioPCMBuffer?
    private var stopBuffer: AVAudioPCMBuffer?

    private static let sampleRate: Double = 44_100
    private static let logger = Logger(subsystem: "com.isecret.typoless", category: "FeedbackSound")

    init() {
        audioFormat = AVAudioFormat(
            standardFormatWithSampleRate: Self.sampleRate,
            channels: 1
        )!

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: audioFormat)

        startBuffer = Self.makeBuffer(
            segments: [
                ToneSegment(frequency: 880.00, gain: 0.92, durationMs: 72),
                ToneSegment(frequency: 1318.51, gain: 0.86, durationMs: 84),
            ],
            bridgeMs: 32,
            format: audioFormat
        )
        stopBuffer = Self.makeBuffer(
            segments: [
                ToneSegment(frequency: 1318.51, gain: 0.86, durationMs: 76),
                ToneSegment(frequency: 880.00, gain: 0.92, durationMs: 80),
            ],
            bridgeMs: 32,
            format: audioFormat
        )

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

    // MARK: - Buffer Generation

    private static func makeBuffer(
        segments: [ToneSegment],
        bridgeMs: Int,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let totalDurationMs =
            segments.reduce(0) { $0 + $1.durationMs }
            + max(0, bridgeMs) * max(segments.count - 1, 0)
        let totalFrames = AVAudioFrameCount(
            sampleRate * Double(totalDurationMs) / 1000.0
        )

        guard totalFrames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames),
              let channelData = buffer.floatChannelData?[0]
        else { return nil }

        buffer.frameLength = totalFrames

        for i in 0..<Int(totalFrames) { channelData[i] = 0 }

        let bridgeSamples = Int(sampleRate * Double(max(0, bridgeMs)) / 1000.0)
        var cursor = 0

        for (index, segment) in segments.enumerated() {
            let segmentSamples = Int(sampleRate * Double(segment.durationMs) / 1000.0)
            let attackSamples = max(1, min(segmentSamples / 3, Int(sampleRate * 0.016)))
            let releaseSamples = max(1, min(segmentSamples / 2, Int(sampleRate * 0.05)))

            for localIndex in 0..<segmentSamples {
                let absoluteIndex = cursor + localIndex
                guard absoluteIndex < Int(totalFrames) else { break }

                let t = Double(localIndex) / sampleRate
                let progress = Double(localIndex) / Double(max(segmentSamples - 1, 1))
                let baseValue = sin(2.0 * .pi * segment.frequency * t)

                var envelope = gaussianEnvelope(progress)
                if localIndex < attackSamples {
                    envelope *= sineEase(Double(localIndex) / Double(attackSamples))
                }

                let releaseStart = segmentSamples - releaseSamples
                if localIndex >= releaseStart {
                    let releaseProgress = Double(segmentSamples - 1 - localIndex) / Double(releaseSamples)
                    envelope *= sineEase(max(0, releaseProgress))
                }

                let amplitude = 0.5
                let value = baseValue * segment.gain * amplitude * envelope
                channelData[absoluteIndex] = Float(value)
            }

            cursor += segmentSamples
            if index < segments.count - 1 {
                cursor += bridgeSamples
            }
        }

        return buffer
    }

    private static func gaussianEnvelope(_ x: Double) -> Double {
        let clamped = min(max(x, 0), 1)
        let sigma = 0.22
        let distance = (clamped - 0.5) / sigma
        let peak = exp(-0.5 * distance * distance)
        let edgeDistance = 0.5 / sigma
        let edge = exp(-0.5 * edgeDistance * edgeDistance)
        return max(0, (peak - edge) / (1 - edge))
    }

    private static func sineEase(_ x: Double) -> Double {
        sin(min(max(x, 0), 1) * (.pi / 2))
    }
}
