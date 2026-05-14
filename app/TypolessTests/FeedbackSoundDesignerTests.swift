import AVFoundation
import XCTest
@testable import Typoless

final class FeedbackSoundDesignerTests: XCTestCase {

    func testPreviewWAVDataHasWaveHeader() throws {
        let wavData = try FeedbackSoundDesigner.makePreviewWAVData(for: .start)

        XCTAssertGreaterThan(wavData.count, 44)
        XCTAssertEqual(String(data: wavData.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wavData.subdata(in: 8..<12), encoding: .ascii), "WAVE")
        XCTAssertEqual(littleEndianUInt16(from: wavData.subdata(in: 22..<24)), 2)
    }

    func testDefaultPreviewMatchesWoodyMalletSpaceHighVariant() throws {
        for cue in FeedbackSoundCue.allCases {
            let defaultData = try FeedbackSoundDesigner.makePreviewWAVData(for: cue)
            let explicitData = try FeedbackSoundDesigner.makePreviewWAVData(
                for: cue,
                timbre: .woodyMalletSpaceHigh
            )
            XCTAssertEqual(defaultData, explicitData, "Default timbre drifted for \(cue)")
        }
    }

    func testBufferIsStereoAndNonEmptyForEachCue() {
        for timbre in FeedbackSoundTimbre.allCases {
            for cue in FeedbackSoundCue.allCases {
                let buffer = FeedbackSoundDesigner.makeBuffer(for: cue, timbre: timbre)

                XCTAssertNotNil(buffer)
                XCTAssertEqual(buffer?.format.channelCount, 2)
                XCTAssertGreaterThan(buffer?.frameLength ?? 0, 0)
            }
        }
    }

    func testStereoImageMatchesTimbreIntent() {
        for timbre in FeedbackSoundTimbre.allCases {
            for cue in FeedbackSoundCue.allCases {
                let differenceEnergy = stereoDifferenceEnergy(for: cue, timbre: timbre)
                let peakDifference = stereoPeakDifference(for: cue, timbre: timbre)

                if timbre.hasStereoSpread {
                    XCTAssertGreaterThan(
                        differenceEnergy,
                        0.5,
                        "Woody variants should keep an audible stereo spread for \(timbre)/\(cue)"
                    )
                    XCTAssertLessThan(
                        peakDifference,
                        0.22,
                        "Woody variant stereo spread is too wide for \(timbre)/\(cue)"
                    )
                } else {
                    XCTAssertLessThan(
                        differenceEnergy,
                        0.000_1,
                        "Only woody mallet should add stereo spread for \(timbre)/\(cue)"
                    )
                }
            }
        }
    }

    func testWoodySpaceVariantsStayDistinctAcrossThreeLevels() {
        let variants: [FeedbackSoundTimbre] = [
            .woodyMallet,
            .woodyMalletSpaceLow,
            .woodyMalletSpaceMedium,
            .woodyMalletSpaceHigh,
        ]

        for cue in FeedbackSoundCue.allCases {
            let lengths = variants.map { FeedbackSoundDesigner.makeBuffer(for: cue, timbre: $0)?.frameLength ?? 0 }

            XCTAssertLessThan(
                lengths[0],
                lengths[1],
                "Low space variant should exceed baseline tail length for \(cue)"
            )
            XCTAssertLessThan(
                lengths[1],
                lengths[2],
                "Medium space variant should exceed low tail length for \(cue)"
            )
            XCTAssertLessThan(
                lengths[2],
                lengths[3],
                "High space variant should exceed medium tail length for \(cue)"
            )

            XCTAssertGreaterThan(
                waveformDifferenceEnergy(for: cue, timbreA: .woodyMalletSpaceLow, timbreB: .woodyMalletSpaceMedium),
                10,
                "Low and medium space variants should not collapse to the same waveform for \(cue)"
            )
            XCTAssertGreaterThan(
                waveformDifferenceEnergy(for: cue, timbreA: .woodyMalletSpaceMedium, timbreB: .woodyMalletSpaceHigh),
                10,
                "Medium and high space variants should not collapse to the same waveform for \(cue)"
            )
        }
    }

    func testCueFrameLengthMatchesDryAndTailProfiles() {
        let dryFrameLengths: [FeedbackSoundCue: AVAudioFrameCount] = [
            .start: 10_848,
            .stop: 11_025,
        ]

        for timbre in FeedbackSoundTimbre.allCases {
            for cue in FeedbackSoundCue.allCases {
                let buffer = FeedbackSoundDesigner.makeBuffer(for: cue, timbre: timbre)
                if timbre.hasStereoSpread {
                    XCTAssertGreaterThan(
                        buffer?.frameLength ?? 0,
                        dryFrameLengths[cue] ?? 0,
                        "Woody tail should extend frame length for \(timbre)/\(cue)"
                    )
                } else {
                    XCTAssertEqual(
                        buffer?.frameLength,
                        dryFrameLengths[cue],
                        "Unexpected dry frame length for \(timbre)/\(cue)"
                    )
                }
            }
        }

        let variants: [FeedbackSoundTimbre] = [
            .woodyMallet,
            .woodyMalletSpaceLow,
            .woodyMalletSpaceMedium,
            .woodyMalletSpaceHigh,
        ]

        for cue in FeedbackSoundCue.allCases {
            let lengths = variants.map { FeedbackSoundDesigner.makeBuffer(for: cue, timbre: $0)?.frameLength ?? 0 }
            XCTAssertLessThan(lengths[0], lengths[1], "Low space tail should be longer than baseline for \(cue)")
            XCTAssertLessThan(lengths[1], lengths[2], "Medium space tail should be longer than low for \(cue)")
            XCTAssertLessThan(lengths[2], lengths[3], "High space tail should be longer than medium for \(cue)")
        }
    }

    func testBufferPeakRemainsWithinNormalizationCeiling() {
        for timbre in FeedbackSoundTimbre.allCases {
            for cue in FeedbackSoundCue.allCases {
                guard
                    let buffer = FeedbackSoundDesigner.makeBuffer(for: cue, timbre: timbre),
                    let channelData = buffer.floatChannelData
                else {
                    XCTFail("Expected buffer for \(timbre)/\(cue)")
                    continue
                }

                let leftChannel = channelData[0]
                let rightChannel = channelData[1]
                var peak: Float = 0

                for index in 0..<Int(buffer.frameLength) {
                    peak = max(peak, abs(leftChannel[index]))
                    peak = max(peak, abs(rightChannel[index]))
                }

                XCTAssertLessThanOrEqual(
                    peak,
                    0.98 + 0.000_1,
                    "Peak exceeded normalization ceiling for \(timbre)/\(cue)"
                )
            }
        }
    }

    func testWoodyMalletWaveformClearlyDiffersFromSoftPiano() {
        let woodyVariants: [FeedbackSoundTimbre] = [
            .woodyMallet,
            .woodyMalletSpaceLow,
            .woodyMalletSpaceMedium,
            .woodyMalletSpaceHigh,
        ]

        for cue in FeedbackSoundCue.allCases {
            guard
                let softPiano = FeedbackSoundDesigner.makeBuffer(for: cue, timbre: .softPiano),
                let softChannels = softPiano.floatChannelData
            else {
                XCTFail("Expected soft piano buffer for \(cue)")
                continue
            }

            for woodyVariant in woodyVariants {
                guard
                    let woodyBuffer = FeedbackSoundDesigner.makeBuffer(for: cue, timbre: woodyVariant),
                    let woodyChannels = woodyBuffer.floatChannelData
                else {
                    XCTFail("Expected woody buffer for \(woodyVariant)/\(cue)")
                    continue
                }

                let sampleCount = min(Int(softPiano.frameLength), Int(woodyBuffer.frameLength))
                var differenceEnergy: Float = 0

                for index in 0..<sampleCount {
                    differenceEnergy += abs(softChannels[0][index] - woodyChannels[0][index])
                }

                XCTAssertGreaterThan(
                    differenceEnergy,
                    25,
                    "\(woodyVariant) is still too close to soft piano for \(cue)"
                )
            }
        }
    }

    func testExportPreviewFilesWritesExpectedPathsAndRemovesLegacyFlatFiles() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        for cue in FeedbackSoundCue.allCases {
            let legacyURL = directoryURL.appendingPathComponent(cue.previewFileName)
            try Data("legacy".utf8).write(to: legacyURL)
        }

        let fileURLs = try FeedbackSoundDesigner.exportPreviewFiles(to: directoryURL)
        let relativePaths = Set(
            fileURLs.map {
                $0.path.replacingOccurrences(of: directoryURL.path + "/", with: "")
            }
        )
        let expectedRelativePaths = Set(
            FeedbackSoundTimbre.allCases.flatMap { timbre in
                FeedbackSoundCue.allCases.map { cue in
                    "\(timbre.previewDirectoryName)/\(cue.previewFileName)"
                }
            }
        )

        XCTAssertEqual(relativePaths, expectedRelativePaths)

        for fileURL in fileURLs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        }

        for cue in FeedbackSoundCue.allCases {
            let legacyURL = directoryURL.appendingPathComponent(cue.previewFileName)
            XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        }
    }

    private func littleEndianUInt16(from data: Data) -> UInt16 {
        UInt16(data[data.startIndex]) | (UInt16(data[data.startIndex + 1]) << 8)
    }

    private func stereoDifferenceEnergy(
        for cue: FeedbackSoundCue,
        timbre: FeedbackSoundTimbre
    ) -> Float {
        guard
            let buffer = FeedbackSoundDesigner.makeBuffer(for: cue, timbre: timbre),
            let channelData = buffer.floatChannelData
        else {
            XCTFail("Expected buffer for \(timbre)/\(cue)")
            return -.greatestFiniteMagnitude
        }

        let leftChannel = channelData[0]
        let rightChannel = channelData[1]
        var differenceEnergy: Float = 0

        for index in 0..<Int(buffer.frameLength) {
            differenceEnergy += abs(leftChannel[index] - rightChannel[index])
        }

        return differenceEnergy
    }

    private func stereoPeakDifference(
        for cue: FeedbackSoundCue,
        timbre: FeedbackSoundTimbre
    ) -> Float {
        guard
            let buffer = FeedbackSoundDesigner.makeBuffer(for: cue, timbre: timbre),
            let channelData = buffer.floatChannelData
        else {
            XCTFail("Expected buffer for \(timbre)/\(cue)")
            return .greatestFiniteMagnitude
        }

        let leftChannel = channelData[0]
        let rightChannel = channelData[1]
        var peakDifference: Float = 0

        for index in 0..<Int(buffer.frameLength) {
            peakDifference = max(peakDifference, abs(leftChannel[index] - rightChannel[index]))
        }

        return peakDifference
    }

    private func waveformDifferenceEnergy(
        for cue: FeedbackSoundCue,
        timbreA: FeedbackSoundTimbre,
        timbreB: FeedbackSoundTimbre
    ) -> Float {
        guard
            let bufferA = FeedbackSoundDesigner.makeBuffer(for: cue, timbre: timbreA),
            let bufferB = FeedbackSoundDesigner.makeBuffer(for: cue, timbre: timbreB),
            let channelsA = bufferA.floatChannelData,
            let channelsB = bufferB.floatChannelData
        else {
            XCTFail("Expected buffers for \(timbreA), \(timbreB), \(cue)")
            return -.greatestFiniteMagnitude
        }

        let sampleCount = min(Int(bufferA.frameLength), Int(bufferB.frameLength))
        var differenceEnergy: Float = 0

        for index in 0..<sampleCount {
            differenceEnergy += abs(channelsA[0][index] - channelsB[0][index])
        }

        differenceEnergy += Float(abs(Int(bufferA.frameLength) - Int(bufferB.frameLength)))

        return differenceEnergy
    }
}
