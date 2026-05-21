import Foundation

/// 已封存的音频分段
struct SealedSegment: Sendable {
    let index: Int
    let pcmData: Data
    let sampleCount: Int
    let sealReason: SealReason
    let voicedDetected: Bool

    /// 音频时长（秒）
    var durationSeconds: Double {
        Double(sampleCount) / Double(AudioSegmenter.sampleRate)
    }

    enum SealReason: String, Sendable {
        case silence = "silence"
        case maxDuration = "max_duration"
        case finalize = "finalize"
    }
}

/// 实时音频分段器
///
/// 接收 PCM 16kHz mono 16-bit 音频块，基于动态噪声底 + dB 阈值检测静音，
/// 在静音边界或 55 秒强制截断处封存分段，通过回调通知调用方。
/// 支持噪声尖峰容忍（轻量语音保护），避免瞬态噪声中断静音检测。
///
/// 线程安全：使用 NSLock 保护内部状态，回调在锁外调用以避免死锁。
/// 采用 `@unchecked Sendable` 而非 actor 以保证低延迟实时处理。
final class AudioSegmenter: @unchecked Sendable {

    // MARK: - Constants

    static let sampleRate: Int = 16_000
    /// 每个分段的最大采样数（55 秒）
    static let maxSegmentSamples: Int = 55 * 16_000  // 880,000
    /// 帧大小（20ms = 320 samples at 16kHz）
    static let frameSamples: Int = 320
    /// 静音持续阈值（1.6 秒 = 25,600 samples）
    static let silenceThresholdSamples: Int = 25_600
    /// 静音切割时保留的尾部语音（300ms = 4,800 samples）
    static let tailPreservationSamples: Int = 4_800
    /// 静音自动切段的最小段长（15 秒 = 240,000 samples），不足 15 秒的段不触发静音切割
    static let minSegmentSamplesForSilenceCut: Int = 15 * 16_000

    // MARK: - 动态噪声底参数

    /// 噪声底 RMS 初始值（覆盖常见麦克风基底噪声）
    static let defaultNoiseFloorRMS: Float = 200.0
    /// 噪声底 RMS 最小值，防止极安静环境导致阈值过低
    static let minNoiseFloorRMS: Float = 10.0
    /// 噪声底 EMA 更新系数（值越小适应越慢、越稳定）
    static let noiseFloorUpdateAlpha: Float = 0.03
    /// 语音判定阈值：帧 RMS 须超过噪声底此 dB 数才算语音（12 dB ≈ 4 倍）
    static let voiceThresholdDB: Float = 12.0
    /// 静音期间容忍的连续噪声尖峰帧数，超过此数量认为是真实语音
    static let maxSpikeFrames: Int = 3

    // MARK: - Callback

    typealias OnSegmentSealed = @Sendable (SealedSegment) -> Void
    var onSegmentSealed: OnSegmentSealed?

    // MARK: - Internal State (protected by lock)

    private let lock = NSLock()
    private var currentPCM = Data()
    private var currentSampleCount: Int = 0
    private var segmentIndex: Int = 0
    private var consecutiveSilentSamples: Int = 0
    private var lastVoicedSampleOffset: Int = 0
    private var voicedDetectedInSegment: Bool = false
    private var finalized: Bool = false
    // 缓冲残余 samples（不足一帧的部分）
    private var residualSamples = Data()
    // 动态噪声底 RMS（EMA 跟踪环境噪声水平）
    private var noiseFloorRMS: Float = AudioSegmenter.defaultNoiseFloorRMS
    // 静音期间连续超阈值帧计数（用于尖峰容忍）
    private var spikeFrameCount: Int = 0

    // MARK: - Public API

    /// 接收一批 PCM 数据，内部按帧分析并在满足条件时封存分段
    func appendPCMChunk(_ chunk: Data) {
        lock.lock()
        guard !finalized else {
            lock.unlock()
            return
        }

        // 将残余 + 新数据合并
        var workData = residualSamples + chunk
        residualSamples = Data()

        var segmentsToEmit: [SealedSegment] = []
        let bytesPerSample = 2  // 16-bit PCM

        while workData.count >= AudioSegmenter.frameSamples * bytesPerSample {
            let frameByteCount = AudioSegmenter.frameSamples * bytesPerSample
            let frameData = workData.prefix(frameByteCount)
            workData = workData.dropFirst(frameByteCount)

            // 检查加入这一帧后是否会超过 maxSegmentSamples
            let samplesAfterFrame = currentSampleCount + AudioSegmenter.frameSamples
            if samplesAfterFrame > AudioSegmenter.maxSegmentSamples {
                // 强制截断：只取到 maxSegmentSamples 边界
                let remainingSamples = AudioSegmenter.maxSegmentSamples - currentSampleCount
                if remainingSamples > 0 {
                    let remainingBytes = remainingSamples * bytesPerSample
                    currentPCM.append(frameData.prefix(remainingBytes))
                    currentSampleCount += remainingSamples
                }

                let segment = makeSealedSegment(reason: .maxDuration)
                segmentsToEmit.append(segment)
                resetSegmentState()

                // 将帧中未使用的部分放回 workData
                let usedBytes = (remainingSamples > 0 ? remainingSamples : 0) * bytesPerSample
                let leftover = frameData.dropFirst(usedBytes)
                if !leftover.isEmpty {
                    workData = leftover + workData
                }
                continue
            }

            // 帧级能量分析（动态噪声底 + dB 阈值）
            let rms = Self.computeFrameRMS(frameData)
            let dynamicThreshold = noiseFloorRMS * pow(10.0, Self.voiceThresholdDB / 20.0)
            let isSilent = rms < dynamicThreshold

            // 用低于阈值的帧更新噪声底 EMA
            if rms < dynamicThreshold {
                noiseFloorRMS = noiseFloorRMS * (1 - Self.noiseFloorUpdateAlpha) + rms * Self.noiseFloorUpdateAlpha
                noiseFloorRMS = max(noiseFloorRMS, Self.minNoiseFloorRMS)
            }

            // 将帧数据加入当前分段
            currentPCM.append(frameData)
            currentSampleCount += AudioSegmenter.frameSamples

            if isSilent {
                spikeFrameCount = 0
                consecutiveSilentSamples += AudioSegmenter.frameSamples
            } else {
                spikeFrameCount += 1
                if spikeFrameCount <= Self.maxSpikeFrames {
                    // 短暂尖峰：容忍，继续累积静音
                    consecutiveSilentSamples += AudioSegmenter.frameSamples
                } else {
                    // 持续语音：确认为真实语音，重置静音计数
                    consecutiveSilentSamples = 0
                    spikeFrameCount = 0
                    lastVoicedSampleOffset = currentSampleCount
                    voicedDetectedInSegment = true
                }
            }

            // 检查是否达到静音阈值（需同时满足 15 秒最小段长要求）
            if consecutiveSilentSamples >= AudioSegmenter.silenceThresholdSamples
                && voicedDetectedInSegment
                && currentSampleCount >= AudioSegmenter.minSegmentSamplesForSilenceCut {
                // 静音切割：回退到 lastVoicedSample + tailPreservation
                let sealPoint = min(
                    lastVoicedSampleOffset + AudioSegmenter.tailPreservationSamples,
                    currentSampleCount
                )
                let sealBytes = sealPoint * bytesPerSample

                let sealedPCM = currentPCM.prefix(sealBytes)
                // 把后面多余的放回 workData 前面
                let excessPCM = currentPCM.dropFirst(sealBytes)

                let segment = SealedSegment(
                    index: segmentIndex,
                    pcmData: Data(sealedPCM),
                    sampleCount: sealPoint,
                    sealReason: .silence,
                    voicedDetected: voicedDetectedInSegment
                )
                segmentsToEmit.append(segment)
                resetSegmentState()

                if !excessPCM.isEmpty {
                    workData = excessPCM + workData
                }
            }
        }

        // 剩余不足一帧的数据保存为残余
        if !workData.isEmpty {
            residualSamples = Data(workData)
        }

        lock.unlock()

        // 在锁外发送回调
        for segment in segmentsToEmit {
            onSegmentSealed?(segment)
        }
    }

    /// 结束录音，封存剩余数据为最终分段
    func finalize() {
        lock.lock()
        guard !finalized else {
            lock.unlock()
            return
        }
        finalized = true

        // 将残余 samples 并入当前分段
        if !residualSamples.isEmpty {
            let bytesPerSample = 2
            let residualSampleCount = residualSamples.count / bytesPerSample
            currentPCM.append(residualSamples.prefix(residualSampleCount * bytesPerSample))
            currentSampleCount += residualSampleCount
            residualSamples = Data()
        }

        var segmentToEmit: SealedSegment?
        if currentSampleCount > 0 {
            segmentToEmit = makeSealedSegment(reason: .finalize)
        }

        lock.unlock()

        if let segment = segmentToEmit {
            onSegmentSealed?(segment)
        }
    }

    /// 重置到初始状态（用于取消后重新开始）
    func reset() {
        lock.lock()
        currentPCM = Data()
        currentSampleCount = 0
        segmentIndex = 0
        consecutiveSilentSamples = 0
        lastVoicedSampleOffset = 0
        voicedDetectedInSegment = false
        finalized = false
        residualSamples = Data()
        noiseFloorRMS = AudioSegmenter.defaultNoiseFloorRMS
        spikeFrameCount = 0
        lock.unlock()
    }

    // MARK: - Private Helpers

    private func makeSealedSegment(reason: SealedSegment.SealReason) -> SealedSegment {
        SealedSegment(
            index: segmentIndex,
            pcmData: currentPCM,
            sampleCount: currentSampleCount,
            sealReason: reason,
            voicedDetected: voicedDetectedInSegment
        )
    }

    private func resetSegmentState() {
        segmentIndex += 1
        currentPCM = Data()
        currentSampleCount = 0
        consecutiveSilentSamples = 0
        lastVoicedSampleOffset = 0
        voicedDetectedInSegment = false
        spikeFrameCount = 0
    }

    /// 计算一帧 PCM 16-bit LE 数据的 RMS 值
    static func computeFrameRMS(_ frameData: Data) -> Float {
        let bytesPerSample = 2
        let sampleCount = frameData.count / bytesPerSample
        guard sampleCount > 0 else { return 0 }

        var sumSquares: Float = 0
        frameData.withUnsafeBytes { rawBuffer in
            let buffer = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                let sample = Float(buffer[i])
                sumSquares += sample * sample
            }
        }

        return (sumSquares / Float(sampleCount)).squareRoot()
    }
}
