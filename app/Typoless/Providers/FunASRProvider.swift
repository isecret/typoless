import Foundation
import os.log

/// FunASR 离线识别 Provider
///
/// 通过 ASRRuntimeManager 管理的 Python sidecar 执行语音识别。
/// 使用 stdio JSON-RPC 协议通信，支持 hotword 参数传入个人词典。
/// 超时、ID 验证、contamination 检测由 ASRRuntimeManager 统一处理。
final class FunASRProvider: ASRProvider, @unchecked Sendable {

    private static let recognizeTimeout: TimeInterval = 15
    private static let warmupTimeout: TimeInterval = 30

    private let logger = Logger(subsystem: "com.isecret.typoless", category: "FunASR")
    private let runtimeManager: ASRRuntimeManager
    private let hotwords: String

    init(runtimeManager: ASRRuntimeManager, hotwords: String = "") {
        self.runtimeManager = runtimeManager
        self.hotwords = hotwords
    }

    // MARK: - ASRProvider

    func recognize(audioData: Data) async throws -> TranscriptResult {
        // 写入临时 WAV 文件供 sidecar 读取
        let tempDir = FileManager.default.temporaryDirectory
        let wavPath = tempDir.appendingPathComponent("typoless_asr_\(UUID().uuidString).wav")

        try audioData.write(to: wavPath)
        defer { try? FileManager.default.removeItem(at: wavPath) }

        var params: [String: Any] = ["wav_path": wavPath.path]
        if !hotwords.isEmpty {
            params["hotwords"] = hotwords
        }

        let result = try await runtimeManager.sendRequest(
            method: "recognize",
            params: params,
            timeout: Self.recognizeTimeout
        )

        let text = result["text"] as? String ?? ""
        let durationMs = result["duration_ms"] as? Int ?? 0

        if text.isEmpty {
            logger.warning("FunASR returned empty text")
        }

        return TranscriptResult(
            text: text,
            requestId: String(result["request_id"] as? Int ?? 0),
            durationMs: durationMs
        )
    }

    // MARK: - Warmup

    /// 触发模型加载和 warmup，建议在首次录音前调用
    func warmup() async throws {
        let result = try await runtimeManager.sendRequest(
            method: "warmup",
            params: [:],
            timeout: Self.warmupTimeout
        )

        if let device = result["device"] as? String {
            logger.info("FunASR warmup complete, device=\(device, privacy: .public)")
        }
    }
}
