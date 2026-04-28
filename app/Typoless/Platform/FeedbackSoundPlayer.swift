import AVFoundation
import Foundation

/// 反馈音效播放器，程序化生成短促音效并即时播放
@MainActor
final class FeedbackSoundPlayer {
    private var startPlayer: AVAudioPlayer?
    private var stopPlayer: AVAudioPlayer?

    init() {
        startPlayer = Self.makePlayer(frequencies: [880, 1175], durationMs: 80, fadeIn: true)
        stopPlayer = Self.makePlayer(frequencies: [1175, 880], durationMs: 80, fadeIn: false)
        startPlayer?.prepareToPlay()
        stopPlayer?.prepareToPlay()
    }

    func playStart() {
        startPlayer?.stop()
        startPlayer?.currentTime = 0
        startPlayer?.play()
    }

    func playStop() {
        stopPlayer?.stop()
        stopPlayer?.currentTime = 0
        stopPlayer?.play()
    }

    // MARK: - WAV Generation

    /// 生成包含双频叠加的短促正弦波 WAV 数据
    private static func makePlayer(frequencies: [Double], durationMs: Int, fadeIn: Bool) -> AVAudioPlayer? {
        let sampleRate: Double = 44_100
        let totalSamples = Int(sampleRate * Double(durationMs) / 1000.0)
        var samples = [Int16](repeating: 0, count: totalSamples)

        for i in 0..<totalSamples {
            let t = Double(i) / sampleRate
            var value: Double = 0

            for freq in frequencies {
                value += sin(2.0 * .pi * freq * t)
            }

            value /= Double(max(frequencies.count, 1))

            // 包络：快速淡入淡出避免咔嗒声
            let fadeLength = min(totalSamples / 5, 200)
            let envelope: Double
            if i < fadeLength {
                envelope = fadeIn ? Double(i) / Double(fadeLength) : 0.7 + 0.3 * Double(i) / Double(fadeLength)
            } else if i > totalSamples - fadeLength {
                envelope = Double(totalSamples - i) / Double(fadeLength)
            } else {
                envelope = 1.0
            }

            let amplitude = 0.35
            samples[i] = Int16(clamping: Int(value * amplitude * envelope * Double(Int16.max)))
        }

        let wavData = wavFileData(samples: samples, sampleRate: Int(sampleRate))
        return try? AVAudioPlayer(data: wavData)
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
