import Foundation

/// 运行时资源校验器，在录音前检查 RNNoise 与 sherpa-onnx 资源是否就绪
struct ResourceValidator: Sendable {

    /// 校验所有新链路所需资源是否存在
    /// 资源缺失时抛出对应的 TypolessError
    static func validateASRResources() throws {
        // sherpa-onnx runtime
        guard let sherpaLib = sherpaLibraryPath(),
              FileManager.default.fileExists(atPath: sherpaLib) else {
            throw TypolessError.asrRuntimeMissing
        }

        // sherpa-onnx model
        let modelDir = sherpaModelDirectory()
        guard let modelDir, FileManager.default.fileExists(atPath: modelDir) else {
            throw TypolessError.asrModelMissing
        }

        // tokens.txt
        let tokensPath = (modelDir as NSString).appendingPathComponent("tokens.txt")
        guard FileManager.default.fileExists(atPath: tokensPath) else {
            throw TypolessError.asrModelMissing
        }

        // 至少一个 encoder 模型文件
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(atPath: modelDir)) ?? []
        let hasEncoder = contents.contains { $0.hasPrefix("encoder") && $0.hasSuffix(".onnx") }
        guard hasEncoder else {
            throw TypolessError.asrModelMissing
        }
    }

    /// 校验 RNNoise 资源
    static func validateDenoiseResources() throws {
        guard let rnnoiseLib = rnnoiseLibraryPath(),
              FileManager.default.fileExists(atPath: rnnoiseLib) else {
            throw TypolessError.audioPreprocessFailure(message: "RNNoise 库未找到，请运行 setup-rnnoise.sh")
        }
    }

    // MARK: - Resource Paths

    static func sherpaLibraryPath() -> String? {
        Bundle.main.resourceURL?
            .appendingPathComponent("sherpa")
            .appendingPathComponent("lib")
            .appendingPathComponent("libsherpa-onnx-c-api.dylib")
            .path
    }

    static func sherpaModelDirectory() -> String? {
        Bundle.main.resourceURL?
            .appendingPathComponent("sherpa")
            .appendingPathComponent("models")
            .appendingPathComponent("streaming-zh")
            .path
    }

    static func rnnoiseLibraryPath() -> String? {
        Bundle.main.resourceURL?
            .appendingPathComponent("rnnoise")
            .appendingPathComponent("lib")
            .appendingPathComponent("librnnoise.dylib")
            .path
    }
}
