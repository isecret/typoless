import Foundation
import XCTest
@testable import Typoless

final class WAVAudioEncoderTests: XCTestCase {
    func testEncodePCM16WritesExpectedWaveHeader() throws {
        let pcmData = Data([0x01, 0x00, 0xff, 0x7f])

        let wavData = WAVAudioEncoder.encodePCM16(
            pcmData: pcmData,
            sampleRate: 16_000,
            channels: 1
        )

        XCTAssertEqual(String(data: wavData.subdata(in: 0..<4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wavData.subdata(in: 8..<12), encoding: .ascii), "WAVE")
        XCTAssertEqual(String(data: wavData.subdata(in: 12..<16), encoding: .ascii), "fmt ")
        XCTAssertEqual(uint16LE(at: 20, in: wavData), 1)
        XCTAssertEqual(uint16LE(at: 22, in: wavData), 1)
        XCTAssertEqual(uint32LE(at: 24, in: wavData), 16_000)
        XCTAssertEqual(uint32LE(at: 28, in: wavData), 32_000)
        XCTAssertEqual(uint16LE(at: 32, in: wavData), 2)
        XCTAssertEqual(uint16LE(at: 34, in: wavData), 16)
        XCTAssertEqual(String(data: wavData.subdata(in: 36..<40), encoding: .ascii), "data")
        XCTAssertEqual(uint32LE(at: 40, in: wavData), UInt32(pcmData.count))
        XCTAssertEqual(wavData.suffix(pcmData.count), pcmData)
    }

    private func uint16LE(at offset: Int, in data: Data) -> UInt16 {
        let bytes = Array(data[offset..<(offset + 2)])
        return UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
    }

    private func uint32LE(at offset: Int, in data: Data) -> UInt32 {
        let bytes = Array(data[offset..<(offset + 4)])
        return UInt32(bytes[0])
            | (UInt32(bytes[1]) << 8)
            | (UInt32(bytes[2]) << 16)
            | (UInt32(bytes[3]) << 24)
    }
}
