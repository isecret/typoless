import Foundation
import XCTest
@testable import Typoless

final class WAVAudioDataExtractorTests: XCTestCase {
    func testExtractPCMDataReturnsDataChunkContents() throws {
        let pcmData = Data([0x01, 0x02, 0x03, 0x04])
        let wavData = makeWAV(with: pcmData)

        let extracted = try WAVAudioDataExtractor.extractPCMData(from: wavData)

        XCTAssertEqual(extracted, pcmData)
    }

    func testExtractPCMDataRejectsInvalidHeader() {
        let invalidData = Data("not-a-wav".utf8)

        XCTAssertThrowsError(try WAVAudioDataExtractor.extractPCMData(from: invalidData))
    }

    private func makeWAV(with pcmData: Data) -> Data {
        var data = Data()
        data.append(Data("RIFF".utf8))
        data.append(uint32LE(UInt32(36 + pcmData.count)))
        data.append(Data("WAVE".utf8))
        data.append(Data("fmt ".utf8))
        data.append(uint32LE(16))
        data.append(uint16LE(1))
        data.append(uint16LE(1))
        data.append(uint32LE(16_000))
        data.append(uint32LE(32_000))
        data.append(uint16LE(2))
        data.append(uint16LE(16))
        data.append(Data("data".utf8))
        data.append(uint32LE(UInt32(pcmData.count)))
        data.append(pcmData)
        return data
    }

    private func uint16LE(_ value: UInt16) -> Data {
        let bytes: [UInt8] = [
            UInt8(value & 0x00ff),
            UInt8((value >> 8) & 0x00ff),
        ]
        return Data(bytes)
    }

    private func uint32LE(_ value: UInt32) -> Data {
        let bytes: [UInt8] = [
            UInt8(value & 0x000000ff),
            UInt8((value >> 8) & 0x000000ff),
            UInt8((value >> 16) & 0x000000ff),
            UInt8((value >> 24) & 0x000000ff),
        ]
        return Data(bytes)
    }
}
