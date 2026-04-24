@preconcurrency import AVFoundation
import Foundation

/// 音频录制器，采集麦克风输入并标准化输出为 PCM/WAV 16kHz mono
final class AudioRecorder: @unchecked Sendable {

    static let maxDuration: TimeInterval = 30
    static let sampleRate: Double = 16_000
    static let channels: AVAudioChannelCount = 1

    private let audioEngine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat

    private let bufferLock = NSLock()
    private var pcmData = Data()
    private var recording = false

    init() {
        outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.sampleRate,
            channels: Self.channels,
            interleaved: true
        )!
    }

    /// 开始录音（MainActor 调用）
    @MainActor
    func startRecording() throws {
        guard !recording else { return }

        bufferLock.lock()
        pcmData = Data()
        bufferLock.unlock()

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioRecorderError.noInputDevice
        }

        guard let newConverter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioRecorderError.converterCreationFailed
        }
        converter = newConverter

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        recording = true
    }

    /// 停止录音并返回 WAV 数据（MainActor 调用）
    @MainActor
    func stopRecording() -> Data {
        guard recording else { return Data() }
        recording = false

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        // Flush converter remaining data
        if let remaining = flushConverter() {
            bufferLock.lock()
            pcmData.append(remaining)
            bufferLock.unlock()
        }
        converter = nil

        bufferLock.lock()
        let finalPCM = pcmData
        pcmData = Data()
        bufferLock.unlock()

        guard !finalPCM.isEmpty else { return Data() }
        return Self.createWAVData(from: finalPCM)
    }

    // MARK: - Buffer Processing

    private func processBuffer(_ inputBuffer: AVAudioPCMBuffer) {
        guard let converter else { return }

        let ratio = Self.sampleRate / inputBuffer.format.sampleRate
        let capacity = max(AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * ratio)), 1)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return
        }

        var error: NSError?
        nonisolated(unsafe) var hasProvided = false

        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if hasProvided {
                outStatus.pointee = .noDataNow
                return nil
            }
            hasProvided = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if error == nil, outputBuffer.frameLength > 0, let channelData = outputBuffer.int16ChannelData {
            let byteCount = Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
            let data = Data(bytes: channelData[0], count: byteCount)
            bufferLock.lock()
            pcmData.append(data)
            bufferLock.unlock()
        }
    }

    private func flushConverter() -> Data? {
        guard let converter else { return nil }
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 1024) else {
            return nil
        }

        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .endOfStream
            return nil
        }

        if error == nil, outputBuffer.frameLength > 0, let channelData = outputBuffer.int16ChannelData {
            let byteCount = Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
            return Data(bytes: channelData[0], count: byteCount)
        }
        return nil
    }

    // MARK: - WAV File Creation

    static func createWAVData(from pcmData: Data) -> Data {
        var wav = Data()
        let sampleRate = UInt32(sampleRate)
        let channels = UInt16(channels)
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcmData.count)
        let fileSize = 36 + dataSize

        // RIFF header
        wav.append(contentsOf: "RIFF".utf8)
        wav.appendLittleEndian(fileSize)
        wav.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        wav.append(contentsOf: "fmt ".utf8)
        wav.appendLittleEndian(UInt32(16))
        wav.appendLittleEndian(UInt16(1)) // PCM
        wav.appendLittleEndian(channels)
        wav.appendLittleEndian(sampleRate)
        wav.appendLittleEndian(byteRate)
        wav.appendLittleEndian(blockAlign)
        wav.appendLittleEndian(bitsPerSample)

        // data chunk
        wav.append(contentsOf: "data".utf8)
        wav.appendLittleEndian(dataSize)
        wav.append(pcmData)

        return wav
    }
}

// MARK: - Errors

enum AudioRecorderError: LocalizedError {
    case noInputDevice
    case converterCreationFailed

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            "未检测到麦克风设备"
        case .converterCreationFailed:
            "无法初始化音频格式转换器"
        }
    }
}

// MARK: - Data Extension

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}
