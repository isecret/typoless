import Foundation
import XCTest
@testable import Typoless

/// 线程安全的 segment 收集器，避免 Swift concurrency 对 captured var 的限制
private final class SegmentCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _segments: [SealedSegment] = []

    var segments: [SealedSegment] {
        lock.withLock { _segments }
    }

    var count: Int {
        lock.withLock { _segments.count }
    }

    func append(_ segment: SealedSegment) {
        lock.withLock { _segments.append(segment) }
    }
}

final class AudioSegmenterTests: XCTestCase {

    // MARK: - Helpers

    /// 生成指定采样数的 PCM 16-bit 数据，振幅控制是否为静音
    private func generatePCM(sampleCount: Int, amplitude: Int16 = 5000) -> Data {
        var data = Data(capacity: sampleCount * 2)
        for _ in 0..<sampleCount {
            var sample = amplitude
            data.append(Data(bytes: &sample, count: 2))
        }
        return data
    }

    /// 生成静音 PCM 数据
    private func generateSilentPCM(sampleCount: Int) -> Data {
        return Data(count: sampleCount * 2)
    }

    private func makeSegmenter() -> (AudioSegmenter, SegmentCollector) {
        let segmenter = AudioSegmenter()
        let collector = SegmentCollector()
        segmenter.onSegmentSealed = { collector.append($0) }
        return (segmenter, collector)
    }

    // MARK: - Frame RMS

    func testComputeFrameRMS_silence() {
        let frame = generateSilentPCM(sampleCount: AudioSegmenter.frameSamples)
        let rms = AudioSegmenter.computeFrameRMS(frame)
        XCTAssertEqual(rms, 0, accuracy: 0.01)
    }

    func testComputeFrameRMS_loudSignal() {
        let frame = generatePCM(sampleCount: AudioSegmenter.frameSamples, amplitude: 10000)
        let rms = AudioSegmenter.computeFrameRMS(frame)
        // 常量振幅信号的 RMS 等于振幅本身
        XCTAssertEqual(rms, 10000, accuracy: 1.0)
    }

    // MARK: - Silence Detection

    func testSilenceCut_triggersSegment() {
        let (segmenter, collector) = makeSegmenter()

        // 发送有声数据（达到 15 秒最小段长要求）
        let voiceData = generatePCM(sampleCount: AudioSegmenter.minSegmentSamplesForSilenceCut, amplitude: 5000)
        segmenter.appendPCMChunk(voiceData)

        // 发送静音数据（超过 1.6 秒阈值 = 25600 samples，多给一些保证触发）
        let silenceData = generateSilentPCM(sampleCount: 28_000)
        segmenter.appendPCMChunk(silenceData)

        XCTAssertEqual(collector.count, 1)
        XCTAssertEqual(collector.segments.first?.sealReason, .silence)
        XCTAssertTrue(collector.segments.first?.voicedDetected ?? false)
    }

    func testSilenceCut_tailPreservation() {
        let (segmenter, collector) = makeSegmenter()

        // 发送有声数据（达到 15 秒最小段长要求）
        let voiceSamples = AudioSegmenter.minSegmentSamplesForSilenceCut
        let voiceData = generatePCM(sampleCount: voiceSamples, amplitude: 5000)
        segmenter.appendPCMChunk(voiceData)

        // 发送静音数据以触发切割
        let silenceData = generateSilentPCM(sampleCount: 28_000)
        segmenter.appendPCMChunk(silenceData)

        let segments = collector.segments
        XCTAssertEqual(segments.count, 1)
        // 封存点应为 lastVoicedSample + tailPreservation
        let expectedMax = voiceSamples + AudioSegmenter.tailPreservationSamples
        XCTAssertLessThanOrEqual(segments[0].sampleCount, expectedMax)
        XCTAssertGreaterThan(segments[0].sampleCount, voiceSamples - AudioSegmenter.frameSamples)
    }

    // MARK: - Forced Cut at 55s

    func testForcedCut_at55Seconds() {
        let (segmenter, collector) = makeSegmenter()

        // 发送超过 55 秒的有声数据（880000 + 一些额外）
        let totalSamples = AudioSegmenter.maxSegmentSamples + 16_000
        // 分多次发送以模拟流式
        let chunkSize = 8000
        var sent = 0
        while sent < totalSamples {
            let remaining = totalSamples - sent
            let thisChunk = min(chunkSize, remaining)
            let chunk = generatePCM(sampleCount: thisChunk, amplitude: 5000)
            segmenter.appendPCMChunk(chunk)
            sent += thisChunk
        }

        let segments = collector.segments
        XCTAssertGreaterThanOrEqual(segments.count, 1)
        // 第一段应该在 maxSegmentSamples 处被截断
        XCTAssertEqual(segments[0].sealReason, .maxDuration)
        XCTAssertEqual(segments[0].sampleCount, AudioSegmenter.maxSegmentSamples)
    }

    // MARK: - Finalize

    func testFinalize_sealsRemaining() {
        let (segmenter, collector) = makeSegmenter()

        let voiceData = generatePCM(sampleCount: 16_000, amplitude: 5000)
        segmenter.appendPCMChunk(voiceData)

        XCTAssertEqual(collector.count, 0)

        segmenter.finalize()

        let segments = collector.segments
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].sealReason, .finalize)
        XCTAssertTrue(segments[0].voicedDetected)
    }

    func testFinalize_silenceOnlySegment() {
        let (segmenter, collector) = makeSegmenter()

        let silenceData = generateSilentPCM(sampleCount: 16_000)
        segmenter.appendPCMChunk(silenceData)

        segmenter.finalize()

        let segments = collector.segments
        XCTAssertEqual(segments.count, 1)
        XCTAssertFalse(segments[0].voicedDetected)
    }

    func testFinalize_doubleCallIgnored() {
        let (segmenter, collector) = makeSegmenter()

        let voiceData = generatePCM(sampleCount: 16_000, amplitude: 5000)
        segmenter.appendPCMChunk(voiceData)

        segmenter.finalize()
        segmenter.finalize()  // 重复调用应被忽略

        XCTAssertEqual(collector.count, 1)
    }

    // MARK: - Reset

    func testReset_clearsState() {
        let (segmenter, collector) = makeSegmenter()

        let voiceData = generatePCM(sampleCount: 16_000, amplitude: 5000)
        segmenter.appendPCMChunk(voiceData)

        segmenter.reset()

        // reset 后旧数据不应被封存
        segmenter.finalize()
        XCTAssertEqual(collector.count, 0)
    }

    // MARK: - Segment Index

    func testSegmentIndex_incrementsCorrectly() {
        let (segmenter, collector) = makeSegmenter()

        // 第一段有声（达到 15 秒最小段长）+ 静音触发切割
        segmenter.appendPCMChunk(generatePCM(sampleCount: AudioSegmenter.minSegmentSamplesForSilenceCut, amplitude: 5000))
        segmenter.appendPCMChunk(generateSilentPCM(sampleCount: 28_000))

        // 第二段有声 + finalize
        segmenter.appendPCMChunk(generatePCM(sampleCount: 16_000, amplitude: 5000))
        segmenter.finalize()

        let segments = collector.segments
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].index, 0)
        XCTAssertEqual(segments[1].index, 1)
    }

    // MARK: - Duration Calculation

    func testDurationSeconds_calculation() {
        let segment = SealedSegment(
            index: 0,
            pcmData: Data(),
            sampleCount: 16_000,
            sealReason: .finalize,
            voicedDetected: true
        )
        XCTAssertEqual(segment.durationSeconds, 1.0, accuracy: 0.001)
    }

    // MARK: - Edge Cases

    func testEmptyChunk_noEffect() {
        let (segmenter, collector) = makeSegmenter()

        segmenter.appendPCMChunk(Data())
        segmenter.finalize()

        XCTAssertEqual(collector.count, 0)
    }

    func testSilenceWithoutVoice_noCut() {
        let (segmenter, collector) = makeSegmenter()

        // 只发送静音（超过阈值），但无有声数据
        let silenceData = generateSilentPCM(sampleCount: 32_000)
        segmenter.appendPCMChunk(silenceData)

        // 不应触发静音切割（因为没有检测到语音）
        XCTAssertEqual(collector.count, 0)
    }

    func testSilenceCut_notTriggeredBelow15Seconds() {
        let (segmenter, collector) = makeSegmenter()

        // 发送 5 秒有声数据（低于 15 秒最小段长）
        let voiceData = generatePCM(sampleCount: 5 * AudioSegmenter.sampleRate, amplitude: 5000)
        segmenter.appendPCMChunk(voiceData)

        // 发送足够静音数据超过阈值
        let silenceData = generateSilentPCM(sampleCount: 28_000)
        segmenter.appendPCMChunk(silenceData)

        // 不应触发静音切割（因为段长未达 15 秒）
        XCTAssertEqual(collector.count, 0)

        // finalize 应正常输出单段
        segmenter.finalize()
        XCTAssertEqual(collector.count, 1)
        XCTAssertEqual(collector.segments[0].sealReason, .finalize)
    }

    // MARK: - 动态噪声底

    func testDynamicNoiseFloor_adaptsDownward() {
        let (segmenter, collector) = makeSegmenter()

        // 先发送足够有声帧确立 voicedDetected（amplitude 5000 远高于默认阈值 ~796）
        let voiceData = generatePCM(sampleCount: AudioSegmenter.minSegmentSamplesForSilenceCut, amplitude: 5000)
        segmenter.appendPCMChunk(voiceData)

        // 发送大量低振幅静音帧，噪声底应从 200 向 0 附近收敛
        // 在收敛后，阈值也会降低，但 RMS=0 始终低于任何正阈值
        let silenceData = generateSilentPCM(sampleCount: 28_000)
        segmenter.appendPCMChunk(silenceData)

        // 静音切段应正常触发（噪声底降低不影响零振幅帧的静音判定）
        XCTAssertEqual(collector.count, 1)
        XCTAssertEqual(collector.segments[0].sealReason, .silence)
    }

    func testDynamicNoiseFloor_highNoiseEnvironment() {
        let (segmenter, collector) = makeSegmenter()

        // 模拟高噪声环境：先发送「有声」帧（amplitude 5000）确立 voicedDetected
        let voiceData = generatePCM(sampleCount: AudioSegmenter.minSegmentSamplesForSilenceCut, amplitude: 5000)
        segmenter.appendPCMChunk(voiceData)

        // 然后发送中等振幅的「环境噪声」帧（amplitude 300，低于默认阈值 ~796）
        // 这些帧 RMS=300 < 动态阈值，被判为静音，同时推高噪声底
        let noiseData = generatePCM(sampleCount: 28_000, amplitude: 300)
        segmenter.appendPCMChunk(noiseData)

        // 即使噪声不为零，只要低于动态阈值，静音切段仍应触发
        XCTAssertEqual(collector.count, 1)
        XCTAssertEqual(collector.segments[0].sealReason, .silence)
    }

    // MARK: - 尖峰容忍

    func testSpikeTolerance_shortSpikesDoNotBreakSilence() {
        let (segmenter, collector) = makeSegmenter()

        // 发送 15 秒有声数据以达到最小段长
        let voiceData = generatePCM(sampleCount: AudioSegmenter.minSegmentSamplesForSilenceCut, amplitude: 5000)
        segmenter.appendPCMChunk(voiceData)

        // 交替发送静音和短尖峰（≤3帧），模拟偶尔的环境噪声
        // 策略：每次发送 0.4 秒静音 + 2 帧尖峰（40ms），循环多次超过 1.6 秒总静音
        for _ in 0..<5 {
            let silence = generateSilentPCM(sampleCount: 6400)  // 0.4s
            segmenter.appendPCMChunk(silence)
            // 2 帧尖峰（≤ maxSpikeFrames=3），不应中断静音累积
            let spike = generatePCM(sampleCount: AudioSegmenter.frameSamples * 2, amplitude: 5000)
            segmenter.appendPCMChunk(spike)
        }

        // 总静音时间 = 5 × 0.4s = 2.0s > 1.6s 阈值
        // 但尖峰帧不更新 voicedDetectedInSegment（只有 >3 帧连续语音才会）
        // 注意：这里 voicedDetectedInSegment 已经在前面的 15s 语音中被设为 true
        // 所以静音切段应该触发
        XCTAssertEqual(collector.count, 1)
        XCTAssertEqual(collector.segments[0].sealReason, .silence)
    }

    func testSpikeTolerance_sustainedVoiceBreaksSilence() {
        let (segmenter, collector) = makeSegmenter()

        // 发送 15 秒有声数据
        let voiceData = generatePCM(sampleCount: AudioSegmenter.minSegmentSamplesForSilenceCut, amplitude: 5000)
        segmenter.appendPCMChunk(voiceData)

        // 发送 1 秒静音
        let silence1 = generateSilentPCM(sampleCount: 16_000)
        segmenter.appendPCMChunk(silence1)

        // 发送 5 帧（100ms）持续语音 — 超过 maxSpikeFrames(3)，应重置静音计数
        let sustainedVoice = generatePCM(sampleCount: AudioSegmenter.frameSamples * 5, amplitude: 5000)
        segmenter.appendPCMChunk(sustainedVoice)

        // 再发送 1.6 秒静音，但加上之前的不够 1.6 秒（因为被重置了）
        // 所以不应切段
        let silence2 = generateSilentPCM(sampleCount: 20_000)  // 1.25s < 1.6s
        segmenter.appendPCMChunk(silence2)

        XCTAssertEqual(collector.count, 0)

        // 再补足够的静音让总静音达到 1.6 秒 → 应触发切段
        let silence3 = generateSilentPCM(sampleCount: 10_000)  // +0.625s
        segmenter.appendPCMChunk(silence3)

        XCTAssertEqual(collector.count, 1)
        XCTAssertEqual(collector.segments[0].sealReason, .silence)
    }

    func testSpikeTolerance_spikesDoNotMarkVoiced() {
        let (segmenter, collector) = makeSegmenter()

        // 只发送静音和短尖峰（≤3帧），不发送持续语音
        // voicedDetectedInSegment 应保持 false
        let silence = generateSilentPCM(sampleCount: AudioSegmenter.minSegmentSamplesForSilenceCut)
        segmenter.appendPCMChunk(silence)

        // 插入 2 帧尖峰
        let spike = generatePCM(sampleCount: AudioSegmenter.frameSamples * 2, amplitude: 5000)
        segmenter.appendPCMChunk(spike)

        // 再追加足够静音超过 1.6 秒
        let moreSilence = generateSilentPCM(sampleCount: 28_000)
        segmenter.appendPCMChunk(moreSilence)

        // 不应触发静音切段（因为 voicedDetectedInSegment 应为 false）
        XCTAssertEqual(collector.count, 0)

        segmenter.finalize()
        XCTAssertEqual(collector.count, 1)
        XCTAssertFalse(collector.segments[0].voicedDetected)
    }
}
