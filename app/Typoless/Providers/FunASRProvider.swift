import Foundation
import os.log

/// FunASR 离线识别 Provider
///
/// 通过 ASRRuntimeManager 管理的 Python sidecar 执行语音识别。
/// 使用 stdio JSON-RPC 协议通信，支持 hotword 参数传入个人词典。
/// 15 秒超时，超时后取消请求并清理 sidecar 状态。
final class FunASRProvider: ASRProvider, @unchecked Sendable {

    private static let recognizeTimeout: TimeInterval = 15
    private static let warmupTimeout: TimeInterval = 30

    private let logger = Logger(subsystem: "com.isecret.typoless", category: "FunASR")
    private let runtimeManager: ASRRuntimeManager
    private let hotwords: String
    private var requestCounter: Int = 0

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

        requestCounter += 1
        let reqID = requestCounter

        var params: [String: Any] = ["wav_path": wavPath.path]
        if !hotwords.isEmpty {
            params["hotwords"] = hotwords
        }

        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "recognize",
            "params": params,
            "id": reqID,
        ]

        // 带超时的识别请求
        let response = try await withTimeout(seconds: Self.recognizeTimeout) {
            try await self.runtimeManager.sendRequest(request)
        }

        guard let result = response["result"] as? [String: Any] else {
            throw TypolessError.asrProcessFailure(message: "Missing result in response")
        }

        let text = result["text"] as? String ?? ""
        let durationMs = result["duration_ms"] as? Int ?? 0

        if text.isEmpty {
            logger.warning("FunASR returned empty text")
        }

        return TranscriptResult(
            text: text,
            requestId: String(reqID),
            durationMs: durationMs
        )
    }

    // MARK: - Warmup

    /// 触发模型加载和 warmup，建议在首次录音前调用
    func warmup() async throws {
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "warmup",
            "params": [:] as [String: Any],
            "id": 0,
        ]

        let response = try await withTimeout(seconds: Self.warmupTimeout) {
            try await self.runtimeManager.sendRequest(request)
        }

        if let result = response["result"] as? [String: Any],
           let device = result["device"] as? String {
            logger.info("FunASR warmup complete, device=\(device, privacy: .public)")
        }
    }

    // MARK: - Timeout

    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw TypolessError.asrProcessFailure(message: "ASR timeout after \(Int(seconds))s")
            }

            guard let result = try await group.next() else {
                throw TypolessError.asrProcessFailure(message: "ASR task group empty")
            }
            group.cancelAll()
            return result
        }
    }
}
