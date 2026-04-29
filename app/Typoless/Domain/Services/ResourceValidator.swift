import Foundation

/// 运行时资源校验器，在录音前检查 ASR 与降噪资源是否就绪
struct ResourceValidator: Sendable {

    /// 校验 FunASR 默认链路所需资源是否存在
    /// 资源缺失时抛出对应的 TypolessError
    static func validateASRResources() throws {
        // FunASR 资源根目录
        let funasrRoot = funasrResourceRoot()
        let fm = FileManager.default

        // manifest.json
        let manifestPath = funasrRoot.appendingPathComponent("manifest.json").path
        guard fm.fileExists(atPath: manifestPath) else {
            throw TypolessError.asrModelMissing
        }

        // 解析 manifest 校验模型目录
        if let data = fm.contents(atPath: manifestPath),
           let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let models = manifest["models"] as? [String: [String: Any]] {
            for (_, model) in models {
                let required = model["required"] as? Bool ?? false
                if required, let path = model["path"] as? String {
                    let fullPath = funasrRoot.appendingPathComponent(path).path
                    guard fm.fileExists(atPath: fullPath) else {
                        throw TypolessError.asrModelMissing
                    }
                }
            }
        }

        // worker 入口脚本
        let workerPath = funasrRoot.appendingPathComponent("worker/funasr_worker.py").path
        guard fm.fileExists(atPath: workerPath) else {
            throw TypolessError.asrBinaryNotFound
        }

        // Python runtime 可用性
        let pythonCandidates = [
            funasrRoot.appendingPathComponent("runtime/python3").path,
            ProcessInfo.processInfo.environment["FUNASR_PYTHON_PATH"],
            "/usr/bin/python3",
        ].compactMap { $0 }

        let hasPython = pythonCandidates.contains { fm.isExecutableFile(atPath: $0) }
        guard hasPython else {
            throw TypolessError.asrRuntimeMissing
        }
    }

    /// 校验旧 sherpa-onnx 链路资源（非默认，仅旧链路使用时校验）
    static func validateSherpaResources() throws {
        guard let sherpaLib = sherpaLibraryPath(),
              FileManager.default.fileExists(atPath: sherpaLib) else {
            throw TypolessError.asrRuntimeMissing
        }

        let modelDir = sherpaModelDirectory()
        guard let modelDir, FileManager.default.fileExists(atPath: modelDir) else {
            throw TypolessError.asrModelMissing
        }

        let tokensPath = (modelDir as NSString).appendingPathComponent("tokens.txt")
        guard FileManager.default.fileExists(atPath: tokensPath) else {
            throw TypolessError.asrModelMissing
        }

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

    static func funasrResourceRoot() -> URL {
        if let envPath = ProcessInfo.processInfo.environment["FUNASR_RESOURCE_PATH"] {
            return URL(fileURLWithPath: envPath)
        }
        return Bundle.main.resourceURL!.appendingPathComponent("funasr")
    }

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
