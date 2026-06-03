import XCTest

final class SherpaOnnxResourceLayoutTests: XCTestCase {
    func testUnversionedOnnxRuntimeIsSymlinkToVersionedBinary() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let libDirectory = repoRoot
            .appendingPathComponent("app")
            .appendingPathComponent("Typoless")
            .appendingPathComponent("Resources")
            .appendingPathComponent("sherpa-onnx")
            .appendingPathComponent("lib")

        let versioned = libDirectory.appendingPathComponent("libonnxruntime.1.24.4.dylib")
        let unversioned = libDirectory.appendingPathComponent("libonnxruntime.dylib")

        XCTAssertTrue(FileManager.default.fileExists(atPath: versioned.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unversioned.path))

        let values = try unversioned.resourceValues(forKeys: [.isSymbolicLinkKey])
        XCTAssertEqual(values.isSymbolicLink, true)

        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: unversioned.path)
        XCTAssertEqual(destination, "libonnxruntime.1.24.4.dylib")
    }
}
