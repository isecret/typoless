import Foundation

/// 基于 sherpa-onnx 的本地流式 ASR Provider
///
/// 通过 dlopen 动态加载 sherpa-onnx C API，支持 partial/final 事件输出。
/// partial 仅用于内部状态、HUD 预览或日志，final 进入 LLM 润色和注入链路。
/// 资源缺失时返回明确错误，不自动回退 Whisper。
final class StreamingASRProvider: ASRProvider, @unchecked Sendable {

    private static let timeout: TimeInterval = 60

    private let hotwordsFilePath: String?

    init(hotwordsFilePath: String? = nil) {
        self.hotwordsFilePath = hotwordsFilePath
    }

    // MARK: - ASRProvider

    func recognize(audioData: Data) async throws -> TranscriptResult {
        let startTime = Date()

        // 解析 WAV PCM 数据
        let pcmSamples = try parseWAVtoFloat32(audioData)

        guard !pcmSamples.isEmpty else {
            throw TypolessError.asrEmptyAudio
        }

        // 加载 sherpa-onnx
        let api = try loadSherpaAPI()

        // 创建识别器
        let recognizer = try createRecognizer(api: api)
        defer { api.destroyRecognizer(recognizer) }

        // 创建流
        let stream = api.createStream(recognizer)
        guard let stream else {
            throw TypolessError.asrProcessFailure(message: "无法创建 sherpa-onnx 识别流")
        }
        defer { api.destroyStream(stream) }

        // 送入音频
        let sampleRate = 16000
        pcmSamples.withUnsafeBufferPointer { buf in
            api.acceptWaveform(stream, Int32(sampleRate), buf.baseAddress!, Int32(buf.count))
        }

        // 标记输入结束
        api.inputFinished(stream)

        // 解码直到完成
        while api.isReady(recognizer, stream) != 0 {
            api.decode(recognizer, stream)
        }

        // 获取结果
        let resultPtr = api.getResult(stream)
        let text: String
        if let resultPtr, let jsonStr = resultPtr.pointee.json {
            let jsonString = String(cString: jsonStr)
            text = Self.extractTextFromJSON(jsonString)
            api.destroyResult(resultPtr)
        } else {
            if let resultPtr {
                api.destroyResult(resultPtr)
            }
            throw TypolessError.asrProcessFailure(message: "sherpa-onnx 识别结果为空")
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TypolessError.asrProcessFailure(message: "sherpa-onnx 识别结果为空")
        }

        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
        return TranscriptResult(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            requestId: nil,
            durationMs: durationMs
        )
    }

    // MARK: - sherpa-onnx C API Types

    private typealias CreateOnlineRecognizer = @convention(c) (UnsafePointer<SherpaOnnxOnlineRecognizerConfig>?) -> OpaquePointer?
    private typealias DestroyOnlineRecognizer = @convention(c) (OpaquePointer?) -> Void
    private typealias CreateOnlineStream = @convention(c) (OpaquePointer?) -> OpaquePointer?
    private typealias DestroyOnlineStream = @convention(c) (OpaquePointer?) -> Void
    private typealias AcceptWaveform = @convention(c) (OpaquePointer?, Int32, UnsafePointer<Float>?, Int32) -> Void
    private typealias InputFinished = @convention(c) (OpaquePointer?) -> Void
    private typealias IsOnlineStreamReady = @convention(c) (OpaquePointer?, OpaquePointer?) -> Int32
    private typealias DecodeOnlineStream = @convention(c) (OpaquePointer?, OpaquePointer?) -> Void
    private typealias GetOnlineStreamResult = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<SherpaOnnxOnlineRecognizerResult>?
    private typealias DestroyOnlineRecognizerResult = @convention(c) (UnsafeMutablePointer<SherpaOnnxOnlineRecognizerResult>?) -> Void

    private struct SherpaOnnxOnlineRecognizerResult {
        var json: UnsafePointer<CChar>?
    }

    // sherpa-onnx config structures (simplified for dlopen usage)
    private struct SherpaOnnxOnlineTransducerModelConfig {
        var encoder: UnsafePointer<CChar>?
        var decoder: UnsafePointer<CChar>?
        var joiner: UnsafePointer<CChar>?
    }

    private struct SherpaOnnxOnlineModelConfig {
        var transducer: SherpaOnnxOnlineTransducerModelConfig
        var tokens: UnsafePointer<CChar>?
        var numThreads: Int32
        var provider: UnsafePointer<CChar>?
        var debug: Int32
        var modelType: UnsafePointer<CChar>?
    }

    private struct SherpaOnnxFeatureConfig {
        var sampleRate: Int32
        var featureDim: Int32
    }

    private struct SherpaOnnxOnlineRecognizerConfig {
        var featConfig: SherpaOnnxFeatureConfig
        var modelConfig: SherpaOnnxOnlineModelConfig
        var decodingMethod: UnsafePointer<CChar>?
        var maxActivePaths: Int32
        var enableEndpoint: Int32
        var rule1MinTrailingSilence: Float
        var rule2MinTrailingSilence: Float
        var rule3MinUtteranceLength: Float
        var hotwordsFile: UnsafePointer<CChar>?
        var hotwordsScore: Float
    }

    private struct SherpaAPI {
        let createRecognizer: CreateOnlineRecognizer
        let destroyRecognizer: DestroyOnlineRecognizer
        let createStream: CreateOnlineStream
        let destroyStream: DestroyOnlineStream
        let acceptWaveform: AcceptWaveform
        let inputFinished: InputFinished
        let isReady: IsOnlineStreamReady
        let decode: DecodeOnlineStream
        let getResult: GetOnlineStreamResult
        let destroyResult: DestroyOnlineRecognizerResult
    }

    // MARK: - Loading

    private func loadSherpaAPI() throws -> SherpaAPI {
        guard let libPath = ResourceValidator.sherpaLibraryPath(),
              FileManager.default.fileExists(atPath: libPath) else {
            throw TypolessError.asrRuntimeMissing
        }

        guard let lib = dlopen(libPath, RTLD_NOW) else {
            let err = String(cString: dlerror())
            throw TypolessError.asrRuntimeMissing
        }

        func loadSym<T>(_ name: String) throws -> T {
            guard let sym = dlsym(lib, name) else {
                throw TypolessError.asrProcessFailure(message: "sherpa-onnx 符号缺失: \(name)")
            }
            return unsafeBitCast(sym, to: T.self)
        }

        return try SherpaAPI(
            createRecognizer: loadSym("SherpaOnnxCreateOnlineRecognizer"),
            destroyRecognizer: loadSym("SherpaOnnxDestroyOnlineRecognizer"),
            createStream: loadSym("SherpaOnnxCreateOnlineStream"),
            destroyStream: loadSym("SherpaOnnxDestroyOnlineStream"),
            acceptWaveform: loadSym("SherpaOnnxOnlineStreamAcceptWaveform"),
            inputFinished: loadSym("SherpaOnnxOnlineStreamInputFinished"),
            isReady: loadSym("SherpaOnnxIsOnlineStreamReady"),
            decode: loadSym("SherpaOnnxDecodeOnlineStream"),
            getResult: loadSym("SherpaOnnxGetOnlineStreamResult"),
            destroyResult: loadSym("SherpaOnnxDestroyOnlineRecognizerResult")
        )
    }

    // MARK: - Recognizer Creation

    private func createRecognizer(api: SherpaAPI) throws -> OpaquePointer {
        guard let modelDir = ResourceValidator.sherpaModelDirectory(),
              FileManager.default.fileExists(atPath: modelDir) else {
            throw TypolessError.asrModelMissing
        }

        // 查找模型文件（支持 int8 变体）
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(atPath: modelDir)) ?? []

        let encoderFile = contents.first { $0.hasPrefix("encoder") && $0.hasSuffix(".onnx") } ?? "encoder.onnx"
        let decoderFile = contents.first { $0.hasPrefix("decoder") && $0.hasSuffix(".onnx") } ?? "decoder.onnx"
        let joinerFile = contents.first { $0.hasPrefix("joiner") && $0.hasSuffix(".onnx") } ?? "joiner.onnx"

        let encoderPath = (modelDir as NSString).appendingPathComponent(encoderFile)
        let decoderPath = (modelDir as NSString).appendingPathComponent(decoderFile)
        let joinerPath = (modelDir as NSString).appendingPathComponent(joinerFile)
        let tokensPath = (modelDir as NSString).appendingPathComponent("tokens.txt")

        // 使用 C 字符串
        return try encoderPath.withCString { encoderCStr in
            try decoderPath.withCString { decoderCStr in
                try joinerPath.withCString { joinerCStr in
                    try tokensPath.withCString { tokensCStr in
                        try "greedy_search".withCString { decodingCStr in
                            try "cpu".withCString { providerCStr in
                                try "".withCString { modelTypeCStr in
                                    let transducerConfig = SherpaOnnxOnlineTransducerModelConfig(
                                        encoder: encoderCStr,
                                        decoder: decoderCStr,
                                        joiner: joinerCStr
                                    )

                                    let modelConfig = SherpaOnnxOnlineModelConfig(
                                        transducer: transducerConfig,
                                        tokens: tokensCStr,
                                        numThreads: 2,
                                        provider: providerCStr,
                                        debug: 0,
                                        modelType: modelTypeCStr
                                    )

                                    let featConfig = SherpaOnnxFeatureConfig(
                                        sampleRate: 16000,
                                        featureDim: 80
                                    )

                                    var config = SherpaOnnxOnlineRecognizerConfig(
                                        featConfig: featConfig,
                                        modelConfig: modelConfig,
                                        decodingMethod: decodingCStr,
                                        maxActivePaths: 4,
                                        enableEndpoint: 1,
                                        rule1MinTrailingSilence: 2.4,
                                        rule2MinTrailingSilence: 1.2,
                                        rule3MinUtteranceLength: 20.0,
                                        hotwordsFile: nil,
                                        hotwordsScore: 1.5
                                    )

                                    // 设置 hotwords（如果有）
                                    if let hwPath = hotwordsFilePath {
                                        return try hwPath.withCString { hwCStr in
                                            config.hotwordsFile = hwCStr
                                            guard let recognizer = api.createRecognizer(&config) else {
                                                throw TypolessError.asrProcessFailure(
                                                    message: "无法初始化 sherpa-onnx 识别器"
                                                )
                                            }
                                            return recognizer
                                        }
                                    } else {
                                        guard let recognizer = api.createRecognizer(&config) else {
                                            throw TypolessError.asrProcessFailure(
                                                message: "无法初始化 sherpa-onnx 识别器"
                                            )
                                        }
                                        return recognizer
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - WAV Parsing

    private func parseWAVtoFloat32(_ data: Data) throws -> [Float] {
        guard data.count > 44 else {
            throw TypolessError.asrEmptyAudio
        }

        let riff = data[0..<4]
        guard String(data: riff, encoding: .ascii) == "RIFF" else {
            throw TypolessError.asrProcessFailure(message: "无效的 WAV 格式")
        }

        // 查找 data chunk
        var offset = 12
        while offset + 8 <= data.count {
            let chunkID = String(data: data[offset..<offset+4], encoding: .ascii) ?? ""
            let chunkSize = data.withUnsafeBytes { buf in
                buf.load(fromByteOffset: offset + 4, as: UInt32.self)
            }

            if chunkID == "data" {
                let pcmStart = offset + 8
                let pcmEnd = min(pcmStart + Int(chunkSize), data.count)
                let pcmData = data[pcmStart..<pcmEnd]

                var int16Samples = [Int16]()
                int16Samples.reserveCapacity(pcmData.count / 2)
                pcmData.withUnsafeBytes { buf in
                    let ptr = buf.bindMemory(to: Int16.self)
                    int16Samples.append(contentsOf: ptr)
                }

                return int16Samples.map { Float($0) / 32768.0 }
            }

            offset += 8 + Int(chunkSize)
            if offset % 2 != 0 { offset += 1 }
        }

        throw TypolessError.asrProcessFailure(message: "WAV 中未找到音频数据")
    }

    // MARK: - Result Parsing

    private static func extractTextFromJSON(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = obj["text"] as? String else {
            return json
        }
        return text
    }
}
