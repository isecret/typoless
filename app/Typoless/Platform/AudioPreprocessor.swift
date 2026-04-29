import Foundation

/// 音频预处理器，使用 RNNoise 对录音进行本地降噪
///
/// RNNoise 通过 dlopen 动态加载，库文件由资源准备脚本放置到 app bundle。
/// 降噪失败时返回明确错误，不静默劣化为原音频。不保存降噪前后的音频历史。
final class AudioPreprocessor: Sendable {

    /// RNNoise 期望的采样率
    private static let rnnoiseSampleRate: Int = 48_000
    /// RNNoise 每帧样本数（固定 480）
    private static let rnnoiseFrameSize: Int = 480
    /// 应用录音采样率
    private static let appSampleRate: Int = 16_000

    // MARK: - RNNoise FFI Typedefs

    private typealias RNNoiseCreateFunc = @convention(c) () -> OpaquePointer?
    private typealias RNNoiseDestroyFunc = @convention(c) (OpaquePointer?) -> Void
    private typealias RNNoiseProcessFrameFunc = @convention(c) (OpaquePointer?, UnsafeMutablePointer<Float>?) -> Float

    // MARK: - Public API

    /// 对 16kHz mono WAV 音频执行降噪，返回降噪后的 16kHz mono WAV
    func denoise(wavData: Data) throws -> Data {
        let handle = try loadRNNoise()
        defer { handle.destroy(handle.state) }

        // 解析 WAV 获取 PCM 样本
        let pcm16k = try parseWAVtoPCM16(wavData)

        // 上采样到 48kHz（RNNoise 要求）
        let pcm48k = resample16kTo48k(pcm16k)

        // 转为 Float 并逐帧降噪
        var floatSamples = pcm48k.map { Float($0) }
        let frameSize = Self.rnnoiseFrameSize

        var offset = 0
        while offset + frameSize <= floatSamples.count {
            floatSamples.withUnsafeMutableBufferPointer { buffer in
                let framePtr = buffer.baseAddress! + offset
                _ = handle.processFrame(handle.state, framePtr)
            }
            offset += frameSize
        }

        // 转回 Int16
        let denoisedPCM48k = floatSamples.map { sample -> Int16 in
            let clamped = max(-32768.0, min(32767.0, sample))
            return Int16(clamped)
        }

        // 下采样回 16kHz
        let denoisedPCM16k = resample48kTo16k(denoisedPCM48k)

        // 重新封装为 WAV
        return buildWAV(from: denoisedPCM16k, sampleRate: Self.appSampleRate)
    }

    // MARK: - RNNoise Loading

    private struct RNNoiseHandle {
        let state: OpaquePointer
        let destroy: RNNoiseDestroyFunc
        let processFrame: RNNoiseProcessFrameFunc
    }

    private func loadRNNoise() throws -> RNNoiseHandle {
        guard let libPath = Self.rnnoiseLibraryPath() else {
            throw TypolessError.audioPreprocessFailure(message: "RNNoise 库文件未找到")
        }

        guard let lib = dlopen(libPath, RTLD_NOW) else {
            let err = String(cString: dlerror())
            throw TypolessError.audioPreprocessFailure(message: "无法加载 RNNoise: \(err)")
        }

        guard let createSym = dlsym(lib, "rnnoise_create"),
              let destroySym = dlsym(lib, "rnnoise_destroy"),
              let processSym = dlsym(lib, "rnnoise_process_frame") else {
            dlclose(lib)
            throw TypolessError.audioPreprocessFailure(message: "RNNoise 符号加载失败")
        }

        let create = unsafeBitCast(createSym, to: RNNoiseCreateFunc.self)
        let destroy = unsafeBitCast(destroySym, to: RNNoiseDestroyFunc.self)
        let processFrame = unsafeBitCast(processSym, to: RNNoiseProcessFrameFunc.self)

        guard let state = create() else {
            dlclose(lib)
            throw TypolessError.audioPreprocessFailure(message: "RNNoise 初始化失败")
        }

        return RNNoiseHandle(state: state, destroy: destroy, processFrame: processFrame)
    }

    private static func rnnoiseLibraryPath() -> String? {
        if let resourceURL = Bundle.main.resourceURL {
            let path = resourceURL
                .appendingPathComponent("rnnoise")
                .appendingPathComponent("lib")
                .appendingPathComponent("librnnoise.dylib")
                .path
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    // MARK: - WAV Parsing

    private func parseWAVtoPCM16(_ data: Data) throws -> [Int16] {
        guard data.count > 44 else {
            throw TypolessError.audioPreprocessFailure(message: "WAV 数据过短")
        }

        // 验证 RIFF 头
        let riff = data[0..<4]
        guard String(data: riff, encoding: .ascii) == "RIFF" else {
            throw TypolessError.audioPreprocessFailure(message: "无效的 WAV 格式")
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

                var samples = [Int16]()
                samples.reserveCapacity(pcmData.count / 2)

                pcmData.withUnsafeBytes { buf in
                    let ptr = buf.bindMemory(to: Int16.self)
                    samples.append(contentsOf: ptr)
                }
                return samples
            }

            offset += 8 + Int(chunkSize)
            if offset % 2 != 0 { offset += 1 }
        }

        throw TypolessError.audioPreprocessFailure(message: "WAV 中未找到音频数据")
    }

    // MARK: - Resampling

    /// 简单线性插值：16kHz → 48kHz (3x)
    private func resample16kTo48k(_ samples: [Int16]) -> [Int16] {
        guard !samples.isEmpty else { return [] }
        let ratio = 3
        var result = [Int16]()
        result.reserveCapacity(samples.count * ratio)

        for i in 0..<samples.count - 1 {
            let current = Float(samples[i])
            let next = Float(samples[i + 1])
            for j in 0..<ratio {
                let t = Float(j) / Float(ratio)
                let interpolated = current + (next - current) * t
                result.append(Int16(max(-32768, min(32767, interpolated))))
            }
        }
        // 最后一个样本
        for _ in 0..<ratio {
            result.append(samples.last!)
        }

        return result
    }

    /// 简单降采样：48kHz → 16kHz (取每3个样本)
    private func resample48kTo16k(_ samples: [Int16]) -> [Int16] {
        stride(from: 0, to: samples.count, by: 3).map { samples[$0] }
    }

    // MARK: - WAV Building

    private func buildWAV(from samples: [Int16], sampleRate: Int) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count * 2)
        let fileSize = 36 + dataSize

        var data = Data()
        data.reserveCapacity(44 + Int(dataSize))

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        samples.withUnsafeBufferPointer { buf in
            data.append(UnsafeBufferPointer(
                start: UnsafeRawPointer(buf.baseAddress!).assumingMemoryBound(to: UInt8.self),
                count: buf.count * 2
            ))
        }

        return data
    }
}
