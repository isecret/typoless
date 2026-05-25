import Foundation

/// 运行时资源校验器，在录音前检查 ASR 与降噪资源是否就绪
struct ResourceValidator: Sendable {

    /// 校验 SenseVoice 默认链路所需资源是否存在
    /// 资源缺失时抛出对应的 TypolessError
    /// 本地模型必须存在于用户目录 ~/.typoless/models/sensevoice-small-onnx，App bundle 不提供模型兜底
    static func validateASRResources() throws {
        let sherpaRoot = sherpaOnnxResourceRoot()
        let modelRoot = LocalASRConfig.modelRoot
        let fm = FileManager.default

        for fileName in LocalASRConfig.requiredFileNames {
            let modelPath = modelRoot.appendingPathComponent(fileName)
            guard fm.fileExists(atPath: modelPath.path),
                  ((try? modelPath.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0 else {
                throw TypolessError.asrModelMissing
            }
        }

        let requiredRuntimeFiles = [
            "lib/libsherpa-onnx-c-api.dylib",
            "lib/libonnxruntime.1.24.4.dylib",
            "include/sherpa-onnx/c-api/c-api.h",
        ]
        for relativePath in requiredRuntimeFiles {
            guard fm.fileExists(atPath: sherpaRoot.appendingPathComponent(relativePath).path) else {
                throw TypolessError.asrRuntimeMissing
            }
        }

        let cAPILibraryPath = sherpaRoot.appendingPathComponent("lib/libsherpa-onnx-c-api.dylib").path
        guard fm.fileExists(atPath: cAPILibraryPath) else {
            throw TypolessError.asrRuntimeMissing
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

    static func sherpaOnnxResourceRoot() -> URL {
        if let envPath = ProcessInfo.processInfo.environment["SHERPA_ONNX_RESOURCE_PATH"] {
            return URL(fileURLWithPath: envPath)
        }
        return Bundle.main.resourceURL!.appendingPathComponent("sherpa-onnx")
    }

    static func rnnoiseLibraryPath() -> String? {
        Bundle.main.resourceURL?
            .appendingPathComponent("rnnoise")
            .appendingPathComponent("lib")
            .appendingPathComponent("librnnoise.dylib")
            .path
    }
}
