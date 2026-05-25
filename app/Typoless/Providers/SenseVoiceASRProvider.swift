import Foundation
import os.log

final class SenseVoiceASRProvider: ASRProvider, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.isecret.typoless", category: "SenseVoiceASR")
    private let runtimeManager: SenseVoiceRuntimeManager

    init(runtimeManager: SenseVoiceRuntimeManager) {
        self.runtimeManager = runtimeManager
    }

    func recognize(audioData: Data, timeout: TimeInterval? = nil) async throws -> TranscriptResult {
        let decoded = try Self.decodePCM16MonoWAV(audioData)
        let start = Date()
        let text = try await runtimeManager.recognize(
            samples: decoded.samples,
            sampleRate: decoded.sampleRate,
            timeout: timeout ?? 15
        )
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)

        if text.isEmpty {
            logger.warning("SenseVoice returned empty text")
        }

        return TranscriptResult(
            text: text,
            requestId: UUID().uuidString,
            durationMs: durationMs
        )
    }

    func warmup() async throws {
        try await runtimeManager.warmup().value
    }

    private static func decodePCM16MonoWAV(_ wavData: Data) throws -> (samples: [Float], sampleRate: Int32) {
        guard wavData.count >= 44 else {
            throw TypolessError.asrEmptyAudio
        }

        guard String(data: wavData.prefix(4), encoding: .ascii) == "RIFF",
              String(data: wavData.subdata(in: 8..<12), encoding: .ascii) == "WAVE" else {
            throw TypolessError.cloudASRInvalidResponse(detail: "无效的 WAV 文件头")
        }

        var offset = 12
        var sampleRate: Int32 = 16_000
        var bitsPerSample = 16
        var channels = 1
        var pcmData: Data?

        while offset + 8 <= wavData.count {
            let chunkID = String(data: wavData.subdata(in: offset..<(offset + 4)), encoding: .ascii)
            let chunkSize = Int(littleEndianUInt32(from: wavData.subdata(in: (offset + 4)..<(offset + 8))))
            let dataStart = offset + 8
            let dataEnd = dataStart + chunkSize

            guard dataEnd <= wavData.count else {
                throw TypolessError.cloudASRInvalidResponse(detail: "WAV 数据块越界")
            }

            if chunkID == "fmt ", chunkSize >= 16 {
                let formatData = wavData.subdata(in: dataStart..<dataEnd)
                let audioFormat = littleEndianUInt16(from: formatData.subdata(in: 0..<2))
                channels = Int(littleEndianUInt16(from: formatData.subdata(in: 2..<4)))
                sampleRate = Int32(littleEndianUInt32(from: formatData.subdata(in: 4..<8)))
                bitsPerSample = Int(littleEndianUInt16(from: formatData.subdata(in: 14..<16)))
                guard audioFormat == 1 else {
                    throw TypolessError.cloudASRInvalidResponse(detail: "SenseVoice 仅支持 PCM WAV")
                }
            } else if chunkID == "data" {
                pcmData = wavData.subdata(in: dataStart..<dataEnd)
            }

            offset = dataEnd
            if offset % 2 != 0 {
                offset += 1
            }
        }

        guard bitsPerSample == 16 else {
            throw TypolessError.cloudASRInvalidResponse(detail: "SenseVoice 仅支持 16-bit PCM WAV")
        }
        guard channels == 1 else {
            throw TypolessError.cloudASRInvalidResponse(detail: "SenseVoice 仅支持 mono WAV")
        }
        guard let pcmData, !pcmData.isEmpty else {
            throw TypolessError.asrEmptyAudio
        }

        let sampleCount = pcmData.count / MemoryLayout<Int16>.size
        var samples: [Float] = []
        samples.reserveCapacity(sampleCount)

        for index in 0..<sampleCount {
            let byteOffset = index * 2
            let lo = UInt16(pcmData[byteOffset])
            let hi = UInt16(pcmData[byteOffset + 1]) << 8
            let value = Int16(bitPattern: lo | hi)
            samples.append(max(-1, Float(value) / 32768.0))
        }

        return (samples, sampleRate)
    }

    private static func littleEndianUInt16(from data: Data) -> UInt16 {
        let bytes = Array(data.prefix(2))
        guard bytes.count == 2 else { return 0 }
        return UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
    }

    private static func littleEndianUInt32(from data: Data) -> UInt32 {
        let bytes = Array(data.prefix(4))
        guard bytes.count == 4 else { return 0 }
        return UInt32(bytes[0])
            | (UInt32(bytes[1]) << 8)
            | (UInt32(bytes[2]) << 16)
            | (UInt32(bytes[3]) << 24)
    }
}
