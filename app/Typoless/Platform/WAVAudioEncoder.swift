import Foundation

enum WAVAudioEncoder {
    static func encodePCM16(
        pcmData: Data,
        sampleRate: Int,
        channels: Int
    ) -> Data {
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8

        var data = Data()
        data.append(Data("RIFF".utf8))
        data.append(uint32LE(UInt32(36 + pcmData.count)))
        data.append(Data("WAVE".utf8))
        data.append(Data("fmt ".utf8))
        data.append(uint32LE(16))
        data.append(uint16LE(1))
        data.append(uint16LE(UInt16(channels)))
        data.append(uint32LE(UInt32(sampleRate)))
        data.append(uint32LE(UInt32(byteRate)))
        data.append(uint16LE(UInt16(blockAlign)))
        data.append(uint16LE(UInt16(bitsPerSample)))
        data.append(Data("data".utf8))
        data.append(uint32LE(UInt32(pcmData.count)))
        data.append(pcmData)
        return data
    }

    private static func uint16LE(_ value: UInt16) -> Data {
        Data([
            UInt8(value & 0x00ff),
            UInt8((value >> 8) & 0x00ff),
        ])
    }

    private static func uint32LE(_ value: UInt32) -> Data {
        Data([
            UInt8(value & 0x000000ff),
            UInt8((value >> 8) & 0x000000ff),
            UInt8((value >> 16) & 0x000000ff),
            UInt8((value >> 24) & 0x000000ff),
        ])
    }
}
