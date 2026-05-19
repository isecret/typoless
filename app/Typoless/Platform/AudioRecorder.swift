import AVFoundation
import Foundation

/// 音频录制器，直接采集为 PCM/WAV 16kHz mono，并支持指定输入设备
final class AudioRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {

    static let maxDuration: TimeInterval = 60
    static let sampleRate: Double = 16_000
    static let channels: Int = 1

    /// 低于此阈值的录音视为误触，静默取消
    static let shortRecordingThreshold: TimeInterval = 0.5

    private var captureSession: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    private let captureQueue = DispatchQueue(label: "typoless.audio.capture")
    private let sampleLock = NSLock()
    private var capturedPCMData = Data()
    private var latestLevel: Float = 0
    private var recording = false
    private var recordingStartTime: Date?

    /// 开始录音（MainActor 调用）
    @MainActor
    func startRecording(device: AVCaptureDevice?) throws {
        guard !recording else { return }

        cleanupRecordingState()

        let captureDevice: AVCaptureDevice?
        if let device {
            captureDevice = device
        } else {
            captureDevice = AVCaptureDevice.default(for: .audio)
        }

        guard let captureDevice else {
            throw AudioRecorderError.noInputDevice
        }

        let session = AVCaptureSession()

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
            let input = try AVCaptureDeviceInput(device: captureDevice)
            let output = AVCaptureAudioDataOutput()
            output.audioSettings = settings
            output.setSampleBufferDelegate(self, queue: captureQueue)

            session.beginConfiguration()
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                throw AudioRecorderError.deviceUnavailable(captureDevice.localizedName)
            }
            session.addInput(input)

            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                throw AudioRecorderError.startFailed
            }
            session.addOutput(output)
            session.commitConfiguration()

            sampleLock.withLock {
                capturedPCMData.removeAll(keepingCapacity: true)
                latestLevel = 0
            }

            captureSession = session
            audioOutput = output

            var didStart = false
            captureQueue.sync {
                session.startRunning()
                didStart = session.isRunning
            }

            guard didStart else {
                output.setSampleBufferDelegate(nil, queue: nil)
                captureSession = nil
                audioOutput = nil
                throw AudioRecorderError.startFailed
            }

            recordingStartTime = Date()
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
        guard recording else { return 0 }
        return sampleLock.withLock { latestLevel }
    }

    /// 停止录音并返回录音结果（含音频数据和录音时长）
    @MainActor
    func stopRecording() -> AudioRecordingResult {
        guard recording else { return AudioRecordingResult(data: Data(), durationMs: 0) }
        recording = false

        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let durationMs = Int(duration * 1000)
        recordingStartTime = nil

        let session = captureSession
        audioOutput?.setSampleBufferDelegate(nil, queue: nil)
        if let session {
            captureQueue.sync {
                if session.isRunning {
                    session.stopRunning()
                }
            }
        }

        let pcmData = sampleLock.withLock { capturedPCMData }
        cleanupRecordingState()

        guard !pcmData.isEmpty else {
            return AudioRecordingResult(data: Data(), durationMs: durationMs)
        }

        let wavData = WAVAudioEncoder.encodePCM16(
            pcmData: pcmData,
            sampleRate: Int(Self.sampleRate),
            channels: Self.channels
        )
        return AudioRecordingResult(data: wavData, durationMs: durationMs)
    }

    @MainActor
    private func cleanupRecordingState() {
        audioOutput?.setSampleBufferDelegate(nil, queue: nil)
        if let captureSession, captureSession.isRunning {
            captureQueue.sync {
                captureSession.stopRunning()
            }
        }
        captureSession = nil
        audioOutput = nil
        recordingStartTime = nil
        recording = false
        sampleLock.withLock {
            capturedPCMData.removeAll(keepingCapacity: true)
            latestLevel = 0
        }
    }

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard CMSampleBufferDataIsReady(sampleBuffer),
              let pcmData = Self.extractPCMData(from: sampleBuffer),
              !pcmData.isEmpty else {
            return
        }

        let level = Self.calculateLevel(fromPCM16Data: pcmData)
        sampleLock.withLock {
            capturedPCMData.append(pcmData)
            latestLevel = level
        }
    }

    private static func extractPCMData(from sampleBuffer: CMSampleBuffer) -> Data? {
        if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
            var lengthAtOffset = 0
            var totalLength = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: &lengthAtOffset,
                totalLengthOut: &totalLength,
                dataPointerOut: &dataPointer
            )
            if status == kCMBlockBufferNoErr, let dataPointer, totalLength > 0 {
                return Data(bytes: dataPointer, count: totalLength)
            }
        }

        var requiredSize = 0
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &requiredSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: nil
        )
        guard status == noErr, requiredSize > 0 else { return nil }

        let rawBufferList = UnsafeMutableRawPointer.allocate(
            byteCount: requiredSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBufferList.deallocate() }

        let audioBufferList = rawBufferList.bindMemory(to: AudioBufferList.self, capacity: 1)
        var retainedBlockBuffer: CMBlockBuffer?
        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: requiredSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &retainedBlockBuffer
        )
        guard status == noErr else { return nil }

        var data = Data()
        for buffer in UnsafeMutableAudioBufferListPointer(audioBufferList) {
            guard let bufferData = buffer.mData, buffer.mDataByteSize > 0 else { continue }
            data.append(Data(bytes: bufferData, count: Int(buffer.mDataByteSize)))
        }
        _ = retainedBlockBuffer
        return data
    }

    private static func calculateLevel(fromPCM16Data data: Data) -> Float {
        data.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            guard !samples.isEmpty else { return 0 }

            var peak: Float = 0
            var sumSquares: Float = 0
            for sample in samples {
                let value = Float(abs(Int(sample))) / Float(Int16.max)
                peak = max(peak, value)
                sumSquares += value * value
            }

            let rms = sqrt(sumSquares / Float(samples.count))
            let mixed = rms * 0.42 + peak * 0.58
            return min(1, powf(mixed, 0.48))
        }
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
    case noInputDevice
    case deviceUnavailable(String)
    case startFailed

    var errorDescription: String? {
        switch self {
        case let .recorderCreationFailed(underlying):
            "无法初始化录音器：\(underlying)"
        case .noInputDevice:
            "未找到可用麦克风"
        case let .deviceUnavailable(name):
            "麦克风不可用：\(name)"
        case .startFailed:
            "录音启动失败"
        }
    }
}
