import AVFoundation
import Foundation

enum FeedbackSoundCue: CaseIterable {
    case start
    case stop

    var previewFileName: String {
        switch self {
        case .start:
            return "feedback-start-soft.wav"
        case .stop:
            return "feedback-stop-soft.wav"
        }
    }
}

enum FeedbackSoundTimbre: String, CaseIterable {
    case softPiano = "soft-piano"
    case woodyMallet = "woody-mallet"
    case woodyMalletSpaceLow = "woody-mallet-space-low"
    case woodyMalletSpaceMedium = "woody-mallet-space-medium"
    case woodyMalletSpaceHigh = "woody-mallet-space-high"
    case musicBox = "music-box"

    private enum WoodySpaceProfile {
        case base
        case low
        case medium
        case high
    }

    var previewDirectoryName: String { rawValue }

    var hasStereoSpread: Bool {
        woodySpaceProfile != nil
    }

    private var woodySpaceProfile: WoodySpaceProfile? {
        switch self {
        case .softPiano, .musicBox:
            return nil
        case .woodyMallet:
            return .base
        case .woodyMalletSpaceLow:
            return .low
        case .woodyMalletSpaceMedium:
            return .medium
        case .woodyMalletSpaceHigh:
            return .high
        }
    }

    fileprivate func layer(
        frequencyMultiplier: Double,
        gain: Double,
        decayRate: Double,
        phaseOffset: Double = 0
    ) -> ToneLayer {
        ToneLayer(
            frequencyMultiplier: frequencyMultiplier,
            gain: gain,
            decayRate: decayRate,
            phaseOffset: phaseOffset
        )
    }

    fileprivate func spec(for cue: FeedbackSoundCue) -> FeedbackSoundSpec {
        switch self {
        case .softPiano:
            return softPianoSpec(for: cue)
        case .musicBox:
            return musicBoxSpec(for: cue)
        case .woodyMallet, .woodyMalletSpaceLow, .woodyMalletSpaceMedium, .woodyMalletSpaceHigh:
            guard let profile = woodySpaceProfile else {
                fatalError("Missing woody space profile for \(self)")
            }
            return woodyMalletSpec(for: cue, profile: profile)
        }
    }

    private func softPianoSpec(for cue: FeedbackSoundCue) -> FeedbackSoundSpec {
        switch cue {
        case .start:
            return FeedbackSoundSpec(
                segments: [
                    ToneSegment(
                        baseFrequency: 587.33,
                        durationMs: 110,
                        layers: [
                            layer(frequencyMultiplier: 1.0, gain: 0.72, decayRate: 0.96),
                            layer(frequencyMultiplier: 2.0, gain: 0.12, decayRate: 2.1, phaseOffset: 0.09),
                            layer(frequencyMultiplier: 3.0, gain: 0.048, decayRate: 3.3, phaseOffset: 0.14),
                            layer(frequencyMultiplier: 4.0, gain: 0.012, decayRate: 5.2, phaseOffset: 0.18),
                        ]
                    ),
                    ToneSegment(
                        baseFrequency: 783.99,
                        durationMs: 118,
                        layers: [
                            layer(frequencyMultiplier: 1.0, gain: 0.68, decayRate: 1.02),
                            layer(frequencyMultiplier: 2.0, gain: 0.105, decayRate: 2.35, phaseOffset: 0.08),
                            layer(frequencyMultiplier: 3.0, gain: 0.04, decayRate: 3.7, phaseOffset: 0.13),
                            layer(frequencyMultiplier: 4.0, gain: 0.010, decayRate: 5.8, phaseOffset: 0.17),
                        ]
                    ),
                ],
                bridgeMs: 18,
                amplitude: 0.22,
                attackMs: 18,
                releaseMs: 92,
                bodyDecayRate: 1.36,
                envelopeStyle: .softPiano,
                transient: nil,
                stereoReflectionTaps: []
            )
        case .stop:
            return FeedbackSoundSpec(
                segments: [
                    ToneSegment(
                        baseFrequency: 783.99,
                        durationMs: 112,
                        layers: [
                            layer(frequencyMultiplier: 1.0, gain: 0.70, decayRate: 0.98),
                            layer(frequencyMultiplier: 2.0, gain: 0.11, decayRate: 2.3, phaseOffset: 0.10),
                            layer(frequencyMultiplier: 3.0, gain: 0.042, decayRate: 3.6, phaseOffset: 0.14),
                            layer(frequencyMultiplier: 4.0, gain: 0.010, decayRate: 5.7, phaseOffset: 0.18),
                        ]
                    ),
                    ToneSegment(
                        baseFrequency: 587.33,
                        durationMs: 120,
                        layers: [
                            layer(frequencyMultiplier: 1.0, gain: 0.74, decayRate: 0.92),
                            layer(frequencyMultiplier: 2.0, gain: 0.13, decayRate: 2.1, phaseOffset: 0.10),
                            layer(frequencyMultiplier: 3.0, gain: 0.046, decayRate: 3.2, phaseOffset: 0.15),
                            layer(frequencyMultiplier: 4.0, gain: 0.011, decayRate: 5.0, phaseOffset: 0.19),
                        ]
                    ),
                ],
                bridgeMs: 18,
                amplitude: 0.22,
                attackMs: 20,
                releaseMs: 96,
                bodyDecayRate: 1.3,
                envelopeStyle: .softPiano,
                transient: nil,
                stereoReflectionTaps: []
            )
        }
    }

    private func woodyMalletSpec(
        for cue: FeedbackSoundCue,
        profile: WoodySpaceProfile
    ) -> FeedbackSoundSpec {
        switch cue {
        case .start:
            return FeedbackSoundSpec(
                segments: [
                    ToneSegment(
                        baseFrequency: 587.33,
                        durationMs: 110,
                        layers: [
                            layer(frequencyMultiplier: 1.0, gain: 0.62, decayRate: 1.55),
                            layer(frequencyMultiplier: 2.76, gain: 0.17, decayRate: 4.2, phaseOffset: 0.21),
                            layer(frequencyMultiplier: 4.03, gain: 0.05, decayRate: 6.6, phaseOffset: 0.39),
                            layer(frequencyMultiplier: 6.41, gain: 0.012, decayRate: 9.4, phaseOffset: 0.58),
                        ]
                    ),
                    ToneSegment(
                        baseFrequency: 783.99,
                        durationMs: 118,
                        layers: [
                            layer(frequencyMultiplier: 1.0, gain: 0.58, decayRate: 1.7),
                            layer(frequencyMultiplier: 2.76, gain: 0.145, decayRate: 4.7, phaseOffset: 0.18),
                            layer(frequencyMultiplier: 4.03, gain: 0.042, decayRate: 7.2, phaseOffset: 0.33),
                            layer(frequencyMultiplier: 6.41, gain: 0.010, decayRate: 10.2, phaseOffset: 0.50),
                        ]
                    ),
                ],
                bridgeMs: 18,
                amplitude: 0.22,
                attackMs: 8,
                releaseMs: 74,
                bodyDecayRate: 2.2,
                envelopeStyle: .woodyMallet,
                transient: TransientSpec(durationMs: 18, gain: 0.28, decayRate: 5.8),
                stereoReflectionTaps: woodyReflectionTaps(for: cue, profile: profile)
            )
        case .stop:
            return FeedbackSoundSpec(
                segments: [
                    ToneSegment(
                        baseFrequency: 783.99,
                        durationMs: 112,
                        layers: [
                            layer(frequencyMultiplier: 1.0, gain: 0.60, decayRate: 1.65),
                            layer(frequencyMultiplier: 2.76, gain: 0.15, decayRate: 4.5, phaseOffset: 0.22),
                            layer(frequencyMultiplier: 4.03, gain: 0.044, decayRate: 6.9, phaseOffset: 0.41),
                            layer(frequencyMultiplier: 6.41, gain: 0.011, decayRate: 9.8, phaseOffset: 0.60),
                        ]
                    ),
                    ToneSegment(
                        baseFrequency: 587.33,
                        durationMs: 120,
                        layers: [
                            layer(frequencyMultiplier: 1.0, gain: 0.64, decayRate: 1.42),
                            layer(frequencyMultiplier: 2.76, gain: 0.17, decayRate: 4.0, phaseOffset: 0.20),
                            layer(frequencyMultiplier: 4.03, gain: 0.048, decayRate: 6.2, phaseOffset: 0.36),
                            layer(frequencyMultiplier: 6.41, gain: 0.012, decayRate: 8.9, phaseOffset: 0.52),
                        ]
                    ),
                ],
                bridgeMs: 18,
                amplitude: 0.22,
                attackMs: 9,
                releaseMs: 78,
                bodyDecayRate: 2.05,
                envelopeStyle: .woodyMallet,
                transient: TransientSpec(durationMs: 19, gain: 0.26, decayRate: 5.4),
                stereoReflectionTaps: woodyReflectionTaps(for: cue, profile: profile)
            )
        }
    }

    private func musicBoxSpec(for cue: FeedbackSoundCue) -> FeedbackSoundSpec {
        switch cue {
        case .start:
            return FeedbackSoundSpec(
                segments: [
                    ToneSegment(
                        baseFrequency: 587.33,
                        durationMs: 110,
                        layers: [
                            layer(frequencyMultiplier: 1.0, gain: 0.54, decayRate: 1.35),
                            layer(frequencyMultiplier: 2.0, gain: 0.18, decayRate: 2.8, phaseOffset: 0.12),
                            layer(frequencyMultiplier: 3.0, gain: 0.09, decayRate: 4.2, phaseOffset: 0.24),
                            layer(frequencyMultiplier: 5.0, gain: 0.022, decayRate: 6.4, phaseOffset: 0.36),
                        ]
                    ),
                    ToneSegment(
                        baseFrequency: 783.99,
                        durationMs: 118,
                        layers: [
                            layer(frequencyMultiplier: 1.0, gain: 0.50, decayRate: 1.5),
                            layer(frequencyMultiplier: 2.0, gain: 0.17, decayRate: 3.0, phaseOffset: 0.11),
                            layer(frequencyMultiplier: 3.0, gain: 0.082, decayRate: 4.6, phaseOffset: 0.22),
                            layer(frequencyMultiplier: 5.0, gain: 0.020, decayRate: 7.0, phaseOffset: 0.34),
                        ]
                    ),
                ],
                bridgeMs: 18,
                amplitude: 0.22,
                attackMs: 14,
                releaseMs: 76,
                bodyDecayRate: 1.95,
                envelopeStyle: .musicBox,
                transient: nil,
                stereoReflectionTaps: []
            )
        case .stop:
            return FeedbackSoundSpec(
                segments: [
                    ToneSegment(
                        baseFrequency: 783.99,
                        durationMs: 112,
                        layers: [
                            layer(frequencyMultiplier: 1.0, gain: 0.52, decayRate: 1.42),
                            layer(frequencyMultiplier: 2.0, gain: 0.18, decayRate: 2.9, phaseOffset: 0.13),
                            layer(frequencyMultiplier: 3.0, gain: 0.084, decayRate: 4.4, phaseOffset: 0.24),
                            layer(frequencyMultiplier: 5.0, gain: 0.020, decayRate: 6.8, phaseOffset: 0.35),
                        ]
                    ),
                    ToneSegment(
                        baseFrequency: 587.33,
                        durationMs: 120,
                        layers: [
                            layer(frequencyMultiplier: 1.0, gain: 0.56, decayRate: 1.28),
                            layer(frequencyMultiplier: 2.0, gain: 0.19, decayRate: 2.7, phaseOffset: 0.12),
                            layer(frequencyMultiplier: 3.0, gain: 0.088, decayRate: 4.1, phaseOffset: 0.23),
                            layer(frequencyMultiplier: 5.0, gain: 0.022, decayRate: 6.2, phaseOffset: 0.33),
                        ]
                    ),
                ],
                bridgeMs: 18,
                amplitude: 0.22,
                attackMs: 15,
                releaseMs: 80,
                bodyDecayRate: 1.82,
                envelopeStyle: .musicBox,
                transient: nil,
                stereoReflectionTaps: []
            )
        }
    }

    private func woodyReflectionTaps(
        for cue: FeedbackSoundCue,
        profile: WoodySpaceProfile
    ) -> [StereoReflectionTap] {
        switch (profile, cue) {
        case (.base, .start):
            return [
                StereoReflectionTap(
                    leftDelayMs: 14,
                    rightDelayMs: 18,
                    leftGain: 0.040,
                    rightGain: 0.032,
                    toneDamping: 0.64
                ),
                StereoReflectionTap(
                    leftDelayMs: 26,
                    rightDelayMs: 31,
                    leftGain: 0.016,
                    rightGain: 0.021,
                    toneDamping: 0.46
                ),
            ]
        case (.base, .stop):
            return [
                StereoReflectionTap(
                    leftDelayMs: 15,
                    rightDelayMs: 19,
                    leftGain: 0.038,
                    rightGain: 0.030,
                    toneDamping: 0.62
                ),
                StereoReflectionTap(
                    leftDelayMs: 28,
                    rightDelayMs: 33,
                    leftGain: 0.015,
                    rightGain: 0.020,
                    toneDamping: 0.44
                ),
            ]
        case (.low, .start):
            return [
                StereoReflectionTap(
                    leftDelayMs: 22,
                    rightDelayMs: 28,
                    leftGain: 0.078,
                    rightGain: 0.064,
                    toneDamping: 0.68
                ),
                StereoReflectionTap(
                    leftDelayMs: 44,
                    rightDelayMs: 52,
                    leftGain: 0.040,
                    rightGain: 0.048,
                    toneDamping: 0.56
                ),
                StereoReflectionTap(
                    leftDelayMs: 68,
                    rightDelayMs: 78,
                    leftGain: 0.016,
                    rightGain: 0.021,
                    toneDamping: 0.40
                ),
            ]
        case (.low, .stop):
            return [
                StereoReflectionTap(
                    leftDelayMs: 23,
                    rightDelayMs: 29,
                    leftGain: 0.076,
                    rightGain: 0.062,
                    toneDamping: 0.66
                ),
                StereoReflectionTap(
                    leftDelayMs: 45,
                    rightDelayMs: 53,
                    leftGain: 0.039,
                    rightGain: 0.047,
                    toneDamping: 0.54
                ),
                StereoReflectionTap(
                    leftDelayMs: 70,
                    rightDelayMs: 80,
                    leftGain: 0.016,
                    rightGain: 0.021,
                    toneDamping: 0.40
                ),
            ]
        case (.medium, .start):
            return [
                StereoReflectionTap(
                    leftDelayMs: 28,
                    rightDelayMs: 36,
                    leftGain: 0.100,
                    rightGain: 0.082,
                    toneDamping: 0.72
                ),
                StereoReflectionTap(
                    leftDelayMs: 58,
                    rightDelayMs: 68,
                    leftGain: 0.056,
                    rightGain: 0.066,
                    toneDamping: 0.60
                ),
                StereoReflectionTap(
                    leftDelayMs: 88,
                    rightDelayMs: 101,
                    leftGain: 0.026,
                    rightGain: 0.033,
                    toneDamping: 0.44
                ),
            ]
        case (.medium, .stop):
            return [
                StereoReflectionTap(
                    leftDelayMs: 29,
                    rightDelayMs: 37,
                    leftGain: 0.098,
                    rightGain: 0.080,
                    toneDamping: 0.70
                ),
                StereoReflectionTap(
                    leftDelayMs: 59,
                    rightDelayMs: 69,
                    leftGain: 0.055,
                    rightGain: 0.065,
                    toneDamping: 0.58
                ),
                StereoReflectionTap(
                    leftDelayMs: 90,
                    rightDelayMs: 103,
                    leftGain: 0.026,
                    rightGain: 0.032,
                    toneDamping: 0.44
                ),
            ]
        case (.high, .start):
            return [
                StereoReflectionTap(
                    leftDelayMs: 36,
                    rightDelayMs: 46,
                    leftGain: 0.122,
                    rightGain: 0.100,
                    toneDamping: 0.74
                ),
                StereoReflectionTap(
                    leftDelayMs: 74,
                    rightDelayMs: 88,
                    leftGain: 0.074,
                    rightGain: 0.086,
                    toneDamping: 0.62
                ),
                StereoReflectionTap(
                    leftDelayMs: 116,
                    rightDelayMs: 134,
                    leftGain: 0.036,
                    rightGain: 0.045,
                    toneDamping: 0.46
                ),
            ]
        case (.high, .stop):
            return [
                StereoReflectionTap(
                    leftDelayMs: 37,
                    rightDelayMs: 47,
                    leftGain: 0.120,
                    rightGain: 0.098,
                    toneDamping: 0.72
                ),
                StereoReflectionTap(
                    leftDelayMs: 76,
                    rightDelayMs: 90,
                    leftGain: 0.072,
                    rightGain: 0.084,
                    toneDamping: 0.60
                ),
                StereoReflectionTap(
                    leftDelayMs: 118,
                    rightDelayMs: 136,
                    leftGain: 0.035,
                    rightGain: 0.044,
                    toneDamping: 0.46
                ),
            ]
        }
    }
}

private enum FeedbackEnvelopeStyle {
    case softPiano
    case woodyMallet
    case musicBox
}

struct FeedbackSoundDesignerError: Error, LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

private struct ToneLayer {
    let frequencyMultiplier: Double
    let gain: Double
    let decayRate: Double
    let phaseOffset: Double

    init(
        frequencyMultiplier: Double,
        gain: Double,
        decayRate: Double,
        phaseOffset: Double = 0
    ) {
        self.frequencyMultiplier = frequencyMultiplier
        self.gain = gain
        self.decayRate = decayRate
        self.phaseOffset = phaseOffset
    }
}

private struct ToneSegment {
    let baseFrequency: Double
    let durationMs: Int
    let layers: [ToneLayer]
}

private struct TransientSpec {
    let durationMs: Int
    let gain: Double
    let decayRate: Double
}

private struct StereoReflectionTap {
    let leftDelayMs: Int
    let rightDelayMs: Int
    let leftGain: Double
    let rightGain: Double
    let toneDamping: Double
}

private struct FeedbackSoundSpec {
    let segments: [ToneSegment]
    let bridgeMs: Int
    let amplitude: Double
    let attackMs: Int
    let releaseMs: Int
    let bodyDecayRate: Double
    let envelopeStyle: FeedbackEnvelopeStyle
    let transient: TransientSpec?
    let stereoReflectionTaps: [StereoReflectionTap]
}

enum FeedbackSoundDesigner {
    static let sampleRate: Double = 44_100
    static let defaultTimbre: FeedbackSoundTimbre = .woodyMalletSpaceHigh

    static func makePlaybackFormat() -> AVAudioFormat {
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        ) else {
            fatalError("Failed to create feedback playback format")
        }

        return format
    }

    static func makeBuffer(for cue: FeedbackSoundCue, format: AVAudioFormat? = nil) -> AVAudioPCMBuffer? {
        makeBuffer(for: cue, timbre: defaultTimbre, format: format)
    }

    static func makeBuffer(
        for cue: FeedbackSoundCue,
        timbre: FeedbackSoundTimbre,
        format: AVAudioFormat? = nil
    ) -> AVAudioPCMBuffer? {
        let format = format ?? makePlaybackFormat()
        let spec = timbre.spec(for: cue)
        let sampleRate = format.sampleRate
        let tailExtensionMs = spec.stereoReflectionTaps.reduce(0) { partialResult, tap in
            max(partialResult, max(tap.leftDelayMs, tap.rightDelayMs))
        }
        let totalDurationMs =
            spec.segments.reduce(0) { $0 + $1.durationMs }
            + max(0, spec.bridgeMs) * max(spec.segments.count - 1, 0)
            + tailExtensionMs
        let totalFrames = AVAudioFrameCount(sampleRate * Double(totalDurationMs) / 1000.0)

        guard totalFrames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames),
              let channelData = buffer.floatChannelData,
              Int(format.channelCount) >= 2
        else {
            return nil
        }

        buffer.frameLength = totalFrames
        let leftChannel = channelData[0]
        let rightChannel = channelData[1]
        var drySamples = Array(repeating: Float(0), count: Int(totalFrames))

        for index in 0..<Int(totalFrames) {
            leftChannel[index] = 0
            rightChannel[index] = 0
        }

        let bridgeSamples = Int(sampleRate * Double(max(0, spec.bridgeMs)) / 1000.0)
        var cursor = 0

        for (index, segment) in spec.segments.enumerated() {
            let segmentSamples = Int(sampleRate * Double(segment.durationMs) / 1000.0)
            let attackSamples = max(1, min(segmentSamples / 2, Int(sampleRate * Double(spec.attackMs) / 1000.0)))
            let releaseSamples = max(1, min(segmentSamples / 2, Int(sampleRate * Double(spec.releaseMs) / 1000.0)))
            let transientSamples = spec.transient.map {
                max(1, Int(sampleRate * Double($0.durationMs) / 1000.0))
            }

            for localIndex in 0..<segmentSamples {
                let absoluteIndex = cursor + localIndex
                guard absoluteIndex < Int(totalFrames) else { break }

                let t = Double(localIndex) / sampleRate
                let progress = Double(localIndex) / Double(max(segmentSamples - 1, 1))
                let baseValue = segment.layers.reduce(into: 0.0) { partialResult, layer in
                    let harmonicDecay = exp(-pow(progress, 0.86) * layer.decayRate)
                    let phase = 2.0 * .pi * segment.baseFrequency * layer.frequencyMultiplier * t + layer.phaseOffset
                    partialResult += sin(phase) * layer.gain * harmonicDecay
                }

                var envelope = envelopeValue(
                    for: spec.envelopeStyle,
                    progress: progress,
                    bodyDecayRate: spec.bodyDecayRate
                )
                if localIndex < attackSamples {
                    envelope *= sineEase(Double(localIndex) / Double(attackSamples))
                }

                let releaseStart = segmentSamples - releaseSamples
                if localIndex >= releaseStart {
                    let releaseProgress = Double(segmentSamples - 1 - localIndex) / Double(releaseSamples)
                    envelope *= sineEase(max(0, releaseProgress))
                }

                var drySample = baseValue * spec.amplitude * envelope
                if let transient = spec.transient, let transientSamples, localIndex < transientSamples {
                    let transientProgress = Double(localIndex) / Double(max(transientSamples - 1, 1))
                    let transientValue = woodyTransient(
                        baseFrequency: segment.baseFrequency,
                        time: t,
                        progress: transientProgress,
                        gain: transient.gain,
                        decayRate: transient.decayRate
                    )
                    drySample += transientValue * spec.amplitude
                }
                drySamples[absoluteIndex] += Float(drySample)
            }

            cursor += segmentSamples
            if index < spec.segments.count - 1 {
                cursor += bridgeSamples
            }
        }

        for index in 0..<Int(totalFrames) {
            let drySample = drySamples[index]
            leftChannel[index] = drySample
            rightChannel[index] = drySample
        }

        applyStereoReflections(
            spec.stereoReflectionTaps,
            from: drySamples,
            leftChannel: leftChannel,
            rightChannel: rightChannel,
            sampleRate: sampleRate
        )

        normalizeIfNeeded(leftChannel: leftChannel, rightChannel: rightChannel, frameCount: Int(totalFrames))

        return buffer
    }

    static func makePreviewWAVData(for cue: FeedbackSoundCue) throws -> Data {
        try makePreviewWAVData(for: cue, timbre: defaultTimbre)
    }

    static func makePreviewWAVData(
        for cue: FeedbackSoundCue,
        timbre: FeedbackSoundTimbre
    ) throws -> Data {
        guard let buffer = makeBuffer(for: cue, timbre: timbre),
              let channelData = buffer.floatChannelData,
              Int(buffer.format.channelCount) >= 2
        else {
            throw FeedbackSoundDesignerError(message: "Failed to render \(timbre.previewDirectoryName)/\(cue.previewFileName)")
        }

        let leftChannel = channelData[0]
        let rightChannel = channelData[1]
        let frameCount = Int(buffer.frameLength)
        var samples: [Int16] = []
        samples.reserveCapacity(frameCount * 2)

        for index in 0..<frameCount {
            let leftSample = max(-1.0, min(1.0, Double(leftChannel[index])))
            let rightSample = max(-1.0, min(1.0, Double(rightChannel[index])))
            samples.append(Int16((leftSample * Double(Int16.max)).rounded()))
            samples.append(Int16((rightSample * Double(Int16.max)).rounded()))
        }

        return buildWAV(
            from: samples,
            sampleRate: Int(sampleRate),
            channelCount: Int(buffer.format.channelCount)
        )
    }

    static func exportPreviewFiles(to directoryURL: URL) throws -> [URL] {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        for cue in FeedbackSoundCue.allCases {
            let legacyURL = directoryURL.appendingPathComponent(cue.previewFileName)
            if FileManager.default.fileExists(atPath: legacyURL.path) {
                try FileManager.default.removeItem(at: legacyURL)
            }
        }

        var fileURLs: [URL] = []
        for timbre in FeedbackSoundTimbre.allCases {
            fileURLs.append(contentsOf: try exportPreviewFiles(for: timbre, to: directoryURL))
        }

        return fileURLs
    }

    static func exportPreviewFiles(
        for timbre: FeedbackSoundTimbre,
        to directoryURL: URL
    ) throws -> [URL] {
        let timbreDirectoryURL = directoryURL.appendingPathComponent(
            timbre.previewDirectoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: timbreDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        var fileURLs: [URL] = []
        for cue in FeedbackSoundCue.allCases {
            let fileURL = timbreDirectoryURL.appendingPathComponent(cue.previewFileName)
            let wavData = try makePreviewWAVData(for: cue, timbre: timbre)
            try wavData.write(to: fileURL, options: .atomic)
            fileURLs.append(fileURL)
        }

        return fileURLs
    }

    private static func envelopeValue(
        for style: FeedbackEnvelopeStyle,
        progress: Double,
        bodyDecayRate: Double
    ) -> Double {
        switch style {
        case .softPiano:
            return softPianoEnvelope(progress, bodyDecayRate: bodyDecayRate)
        case .woodyMallet:
            return woodyMalletEnvelope(progress, bodyDecayRate: bodyDecayRate)
        case .musicBox:
            return musicBoxEnvelope(progress, bodyDecayRate: bodyDecayRate)
        }
    }

    private static func softPianoEnvelope(_ x: Double, bodyDecayRate: Double) -> Double {
        let clamped = min(max(x, 0), 1)
        let body = exp(-clamped * bodyDecayRate)
        let sustain = 0.72 + (1 - clamped) * 0.28
        let tail = pow(max(0, 1 - clamped), 0.18)
        return body * sustain * tail
    }

    private static func woodyMalletEnvelope(_ x: Double, bodyDecayRate: Double) -> Double {
        let clamped = min(max(x, 0), 1)
        let contour = pow(max(0, 1 - clamped), 0.24)
        let decay = exp(-clamped * bodyDecayRate)
        return contour * decay
    }

    private static func musicBoxEnvelope(_ x: Double, bodyDecayRate: Double) -> Double {
        let clamped = min(max(x, 0), 1)
        let chime = exp(-clamped * bodyDecayRate)
        let shimmer = 0.84 + (1 - clamped) * 0.16
        let tail = pow(max(0, 1 - clamped), 0.12)
        return chime * shimmer * tail
    }

    private static func woodyTransient(
        baseFrequency: Double,
        time: Double,
        progress: Double,
        gain: Double,
        decayRate: Double
    ) -> Double {
        let clamped = min(max(progress, 0), 1)
        let envelope = exp(-clamped * decayRate) * pow(max(0, 1 - clamped), 0.42)
        let noiseLikeBody =
            sin(2.0 * .pi * baseFrequency * 1.91 * time + 0.11) * 0.52
            + sin(2.0 * .pi * baseFrequency * 3.73 * time + 0.37) * 0.30
            + sin(2.0 * .pi * baseFrequency * 6.27 * time + 0.71) * 0.18
        let click = sin(2.0 * .pi * baseFrequency * 8.94 * time + 0.23) * 0.12
        return (noiseLikeBody + click) * gain * envelope
    }

    private static func applyStereoReflections(
        _ taps: [StereoReflectionTap],
        from drySamples: [Float],
        leftChannel: UnsafeMutablePointer<Float>,
        rightChannel: UnsafeMutablePointer<Float>,
        sampleRate: Double
    ) {
        guard !taps.isEmpty, !drySamples.isEmpty else { return }

        for tap in taps {
            let leftDelaySamples = max(1, Int(sampleRate * Double(tap.leftDelayMs) / 1000.0))
            let rightDelaySamples = max(1, Int(sampleRate * Double(tap.rightDelayMs) / 1000.0))

            for index in 0..<drySamples.count {
                let sourceSample = Double(drySamples[index])
                let previousSample = index > 0 ? Double(drySamples[index - 1]) : sourceSample
                let dampedSample =
                    (sourceSample * tap.toneDamping)
                    + (previousSample * (1 - tap.toneDamping))

                let leftTarget = index + leftDelaySamples
                if leftTarget < drySamples.count {
                    leftChannel[leftTarget] += Float(dampedSample * tap.leftGain)
                }

                let rightTarget = index + rightDelaySamples
                if rightTarget < drySamples.count {
                    rightChannel[rightTarget] += Float(dampedSample * tap.rightGain)
                }
            }
        }
    }

    private static func sineEase(_ x: Double) -> Double {
        sin(min(max(x, 0), 1) * (.pi / 2))
    }

    private static func normalizeIfNeeded(
        leftChannel: UnsafeMutablePointer<Float>,
        rightChannel: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) {
        var peak = 0.0
        for index in 0..<frameCount {
            peak = max(peak, Double(abs(leftChannel[index])))
            peak = max(peak, Double(abs(rightChannel[index])))
        }

        guard peak > 0.98 else { return }
        let scale = Float(0.98 / peak)
        for index in 0..<frameCount {
            leftChannel[index] *= scale
            rightChannel[index] *= scale
        }
    }

    private static func buildWAV(from samples: [Int16], sampleRate: Int, channelCount: Int) -> Data {
        let numChannels = UInt16(channelCount)
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count * 2)
        let fileSize = 36 + dataSize

        var data = Data()
        data.reserveCapacity(44 + Int(dataSize))

        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        samples.withUnsafeBufferPointer { buffer in
            data.append(
                UnsafeBufferPointer(
                    start: UnsafeRawPointer(buffer.baseAddress!).assumingMemoryBound(to: UInt8.self),
                    count: buffer.count * 2
                )
            )
        }

        return data
    }
}
