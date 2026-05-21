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
        XCTAssertGreaterThan(rms, AudioSegmenter.silenceRMSThreshold)
    }

    // MARK: - Silence Detection

    func testSilenceCut_triggersSegment() {
        let (segmenter, collector) = makeSegmenter()

        // 发送有声数据（2秒 = 32000 samples）
        let voiceData = generatePCM(sampleCount: 32_000, amplitude: 5000)
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

        // 发送有声数据
        let voiceSamples = 16_000  // 1 second
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

        // 第一段有声 + 静音触发切割
        segmenter.appendPCMChunk(generatePCM(sampleCount: 16_000, amplitude: 5000))
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
}
