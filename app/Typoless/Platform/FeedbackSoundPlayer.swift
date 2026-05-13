import AVFoundation
import Foundation

/// 反馈音效播放器，程序化生成短促音效并即时播放
@MainActor
final class FeedbackSoundPlayer {
    private struct ToneSegment {
        let frequency: Double
        let gain: Double
        let durationMs: Int
    }

    private var startPlayer: AVAudioPlayer?
    private var coldStartPlayer: AVAudioPlayer?
    private var stopPlayer: AVAudioPlayer?
    private var lastPlaybackAt: Date?

    private static let coldOutputThreshold: TimeInterval = 5
    private static let coldStartLeadSilenceMs = 140

    init() {
        startPlayer = Self.makePlayer(
            segments: [
                ToneSegment(frequency: 880.00, gain: 0.92, durationMs: 72),
                ToneSegment(frequency: 1318.51, gain: 0.86, durationMs: 84)
            ],
            bridgeMs: 32
        )
        coldStartPlayer = Self.makePlayer(
            segments: [
                ToneSegment(frequency: 880.00, gain: 0.92, durationMs: 72),
                ToneSegment(frequency: 1318.51, gain: 0.86, durationMs: 84)
            ],
            bridgeMs: 32,
            leadingSilenceMs: Self.coldStartLeadSilenceMs
        )
        stopPlayer = Self.makePlayer(
            segments: [
                ToneSegment(frequency: 1318.51, gain: 0.86, durationMs: 76),
                ToneSegment(frequency: 880.00, gain: 0.92, durationMs: 80)
            ],
            bridgeMs: 32
        )
        startPlayer?.prepareToPlay()
        coldStartPlayer?.prepareToPlay()
        stopPlayer?.prepareToPlay()
    }

    func playStart() {
        play(isOutputLikelyCold ? coldStartPlayer : startPlayer)
    }

    func playStop() {
        play(stopPlayer)
    }

    /// 预加载音效数据，减少首次调用时的对象初始化抖动。
    func primeOutputIfNeeded() {
        startPlayer?.prepareToPlay()
        coldStartPlayer?.prepareToPlay()
        stopPlayer?.prepareToPlay()
    }

    private var isOutputLikelyCold: Bool {
        guard let lastPlaybackAt else { return true }
        return Date().timeIntervalSince(lastPlaybackAt) >= Self.coldOutputThreshold
    }

    // MARK: - WAV Generation

    /// 生成带高斯包络的两段式提示音 WAV 数据。
    private static func makePlayer(
        segments: [ToneSegment],
        bridgeMs: Int,
        leadingSilenceMs: Int = 0
    ) -> AVAudioPlayer? {
        let sampleRate: Double = 44_100
        let silenceMs = max(0, leadingSilenceMs)
        let totalDurationMs =
            silenceMs +
            segments.reduce(0) { $0 + $1.durationMs } +
            max(0, bridgeMs) * max(segments.count - 1, 0)
        let totalSamples = Int(sampleRate * Double(totalDurationMs) / 1000.0)
        var samples = [Int16](repeating: 0, count: totalSamples)
        let leadingSilenceSamples = Int(sampleRate * Double(silenceMs) / 1000.0)
        let bridgeSamples = Int(sampleRate * Double(max(0, bridgeMs)) / 1000.0)
        var cursor = leadingSilenceSamples

        for (index, segment) in segments.enumerated() {
            let segmentSamples = Int(sampleRate * Double(segment.durationMs) / 1000.0)
            let attackSamples = max(1, min(segmentSamples / 3, Int(sampleRate * 0.016)))
            let releaseSamples = max(1, min(segmentSamples / 2, Int(sampleRate * 0.05)))

            for localIndex in 0..<segmentSamples {
                let absoluteIndex = cursor + localIndex
                guard absoluteIndex < samples.count else { break }

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

                let amplitude = 0.2
                let value = baseValue * segment.gain * amplitude * envelope
                samples[absoluteIndex] = Int16(clamping: Int(value * Double(Int16.max)))
            }

            cursor += segmentSamples
            if index < segments.count - 1 {
                cursor += bridgeSamples
            }
        }

        let wavData = wavFileData(samples: samples, sampleRate: Int(sampleRate))
        return try? AVAudioPlayer(data: wavData)
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

    private func play(_ player: AVAudioPlayer?) {
        player?.stop()
        player?.currentTime = 0
        player?.volume = 1
        player?.prepareToPlay()
        player?.play()
        lastPlaybackAt = Date()
    }

    /// 构建最小 WAV 文件数据（PCM 16-bit mono）
    private static func wavFileData(samples: [Int16], sampleRate: Int) -> Data {
        var data = Data()
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count * Int(blockAlign))

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        appendUInt32(&data, 36 + dataSize)
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        appendUInt32(&data, 16)
        appendUInt16(&data, 1) // PCM
        appendUInt16(&data, numChannels)
        appendUInt32(&data, UInt32(sampleRate))
        appendUInt32(&data, byteRate)
        appendUInt16(&data, blockAlign)
        appendUInt16(&data, bitsPerSample)

        // data chunk
        data.append(contentsOf: "data".utf8)
        appendUInt32(&data, dataSize)

        for sample in samples {
            appendInt16(&data, sample)
        }

        return data
    }

    private static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        var v = value.littleEndian
        data.append(Data(bytes: &v, count: 4))
    }

    private static func appendUInt16(_ data: inout Data, _ value: UInt16) {
        var v = value.littleEndian
        data.append(Data(bytes: &v, count: 2))
    }

    private static func appendInt16(_ data: inout Data, _ value: Int16) {
        var v = value.littleEndian
        data.append(Data(bytes: &v, count: 2))
    }
}
