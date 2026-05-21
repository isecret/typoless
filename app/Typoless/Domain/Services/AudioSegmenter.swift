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
/// 接收 PCM 16kHz mono 16-bit 音频块，基于帧级能量分析检测静音，
/// 在静音边界或 55 秒强制截断处封存分段，通过回调通知调用方。
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
    /// RMS 能量阈值，低于此值判定为静音帧
    static let silenceRMSThreshold: Float = 80.0

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

            // 帧级能量分析
            let rms = Self.computeFrameRMS(frameData)
            let isSilent = rms < AudioSegmenter.silenceRMSThreshold

            // 将帧数据加入当前分段
            currentPCM.append(frameData)
            currentSampleCount += AudioSegmenter.frameSamples

            if isSilent {
                consecutiveSilentSamples += AudioSegmenter.frameSamples
            } else {
                consecutiveSilentSamples = 0
                lastVoicedSampleOffset = currentSampleCount
                voicedDetectedInSegment = true
            }

            // 检查是否达到静音阈值
            if consecutiveSilentSamples >= AudioSegmenter.silenceThresholdSamples
                && voicedDetectedInSegment {
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
