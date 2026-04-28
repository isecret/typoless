import AVFoundation
import Foundation

/// 音频录制器，直接录制为 PCM/WAV 16kHz mono，避免实时转换链路引发的 CoreAudio 重配置崩溃
final class AudioRecorder: @unchecked Sendable {

    static let maxDuration: TimeInterval = 30
    static let sampleRate: Double = 16_000
    static let channels: Int = 1

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var recording = false

    /// 开始录音（MainActor 调用）
    @MainActor
    func startRecording() throws {
        guard !recording else { return }

        cleanupRecordingFile()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("typoless-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: Self.channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()

            guard recorder.record() else {
                throw AudioRecorderError.startFailed
            }

            self.recorder = recorder
            recordingURL = url
            recording = true
        } catch let error as AudioRecorderError {
            throw error
        } catch {
            throw AudioRecorderError.recorderCreationFailed(underlying: error.localizedDescription)
        }
    }

    /// 返回当前录音电平（0-1 归一化），用于驱动 HUD 声波动画
    @MainActor
    func currentLevel() -> Float {
        guard recording, let recorder else { return 0 }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        // dB → 线性振幅，再用 gamma 曲线增强低音量感知
        let minDb: Float = -50
        let clamped = max(minDb, min(0, power))
        let linear = powf(10, clamped / 20) // 0…1
        let gamma: Float = 0.6
        return powf(linear, gamma)
    }

    /// 停止录音并返回 WAV 数据（MainActor 调用）
    @MainActor
    func stopRecording() -> Data {
        guard recording else { return Data() }
        recording = false

        recorder?.stop()
        recorder = nil

        guard let url = recordingURL else {
            cleanupRecordingFile()
            return Data()
        }

        defer { cleanupRecordingFile() }

        return (try? Data(contentsOf: url)) ?? Data()
    }

    @MainActor
    private func cleanupRecordingFile() {
        recorder?.stop()
        recorder = nil

        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        recording = false
    }
}

enum AudioRecorderError: LocalizedError {
    case recorderCreationFailed(underlying: String)
    case startFailed

    var errorDescription: String? {
        switch self {
        case let .recorderCreationFailed(underlying):
            "无法初始化录音器：\(underlying)"
        case .startFailed:
            "录音启动失败"
        }
    }
}
