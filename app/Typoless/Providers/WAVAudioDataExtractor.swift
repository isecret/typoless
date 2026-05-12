import Foundation

enum WAVAudioDataExtractor {
    static func extractPCMData(from wavData: Data) throws -> Data {
        guard wavData.count >= 44 else {
            throw TypolessError.cloudASRInvalidResponse(detail: "WAV 数据长度异常")
        }

        let riff = String(data: wavData.prefix(4), encoding: .ascii)
        let wave = String(data: wavData.subdata(in: 8..<12), encoding: .ascii)
        guard riff == "RIFF", wave == "WAVE" else {
            throw TypolessError.cloudASRInvalidResponse(detail: "无效的 WAV 文件头")
        }

        var offset = 12
        while offset + 8 <= wavData.count {
            let chunkIDData = wavData.subdata(in: offset..<(offset + 4))
            let chunkID = String(data: chunkIDData, encoding: .ascii)
            let chunkSizeRange = (offset + 4)..<(offset + 8)
            let chunkSize = Int(littleEndianUInt32(from: wavData.subdata(in: chunkSizeRange)))
            let dataStart = offset + 8
            let dataEnd = dataStart + chunkSize

            guard dataEnd <= wavData.count else {
                throw TypolessError.cloudASRInvalidResponse(detail: "WAV 数据块越界")
            }

            if chunkID == "data" {
                return wavData.subdata(in: dataStart..<dataEnd)
            }

            offset = dataEnd
            if offset % 2 != 0 {
                offset += 1
            }
        }

        throw TypolessError.cloudASRInvalidResponse(detail: "WAV 文件缺少 data 数据块")
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
