import AVFoundation
import Foundation

/// 音频录制器，直接录制为 PCM/WAV 16kHz mono，避免实时转换链路引发的 CoreAudio 重配置崩溃
final class AudioRecorder: @unchecked Sendable {

    static let maxDuration: TimeInterval = 60
    static let sampleRate: Double = 16_000
    static let channels: Int = 1

    /// 低于此阈值的录音视为误触，静默取消
    static let shortRecordingThreshold: TimeInterval = 0.5

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var recording = false
    private var recordingStartTime: Date?

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
            recordingStartTime = Date()
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
        let averagePower = recorder.averagePower(forChannel: 0)
        let peakPower = recorder.peakPower(forChannel: 0)
        // 混合 average/peak，让短促发音和爆破音更快体现在 HUD 上
        let minDb: Float = -50
        let averageClamped = max(minDb, min(0, averagePower))
        let peakClamped = max(minDb, min(0, peakPower))
        let averageLinear = powf(10, averageClamped / 20)
        let peakLinear = powf(10, peakClamped / 20)
        let mixed = averageLinear * 0.42 + peakLinear * 0.58
        let gamma: Float = 0.48
        return min(1, powf(mixed, gamma))
    }

    /// 停止录音并返回录音结果（含音频数据和录音时长）
    @MainActor
    func stopRecording() -> AudioRecordingResult {
        guard recording else { return AudioRecordingResult(data: Data(), durationMs: 0) }
        recording = false

        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let durationMs = Int(duration * 1000)
        recordingStartTime = nil

        recorder?.stop()
        recorder = nil

        guard let url = recordingURL else {
            cleanupRecordingFile()
            return AudioRecordingResult(data: Data(), durationMs: durationMs)
        }

        defer { cleanupRecordingFile() }

        let data = (try? Data(contentsOf: url)) ?? Data()
        return AudioRecordingResult(data: data, durationMs: durationMs)
    }

    @MainActor
    private func cleanupRecordingFile() {
        recorder?.stop()
        recorder = nil
        recordingStartTime = nil

        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        recording = false
    }
}

/// 录音结果，包含音频数据和录音时长
struct AudioRecordingResult: Sendable {
    let data: Data
    let durationMs: Int

    /// 录音时长是否低于短录音阈值（500ms）
    var isShortRecording: Bool {
        durationMs < Int(AudioRecorder.shortRecordingThreshold * 1000)
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
