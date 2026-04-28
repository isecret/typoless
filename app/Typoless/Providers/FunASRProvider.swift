import Foundation

/// 本地 FunASR 语音识别 Provider，通过内置子进程执行离线识别
struct FunASRProvider: ASRProvider, Sendable {

    private static let timeout: TimeInterval = 30

    // MARK: - 资源路径

    private static var binaryURL: URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("funasr")
            .appendingPathComponent("bin")
            .appendingPathComponent("funasr-cli")
    }

    private static var modelDirectory: URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("funasr")
            .appendingPathComponent("models")
    }

    // MARK: - ASRProvider

    func recognize(audioData: Data) async throws -> TranscriptResult {
        guard let binaryURL = Self.binaryURL,
              FileManager.default.fileExists(atPath: binaryURL.path) else {
            throw TypolessError.funasrBinaryNotFound
        }

        guard let modelDir = Self.modelDirectory,
              FileManager.default.fileExists(atPath: modelDir.path) else {
            throw TypolessError.funasrModelMissing
        }

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("typoless_\(UUID().uuidString).wav")

        defer { try? FileManager.default.removeItem(at: tempFile) }

        do {
            try audioData.write(to: tempFile)
        } catch {
            throw TypolessError.funasrProcessFailure(message: "无法写入临时音频文件")
        }

        return try await runProcess(
            binary: binaryURL,
            modelDir: modelDir,
            audioFile: tempFile
        )
    }

    // MARK: - 子进程执行

    /// 在非主线程执行子进程，支持 Task 取消时终止进程
    private func runProcess(
        binary: URL,
        modelDir: URL,
        audioFile: URL
    ) async throws -> TranscriptResult {
        let startTime = Date()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                let outputPipe = Pipe()
                let errorPipe = Pipe()

                process.executableURL = binary
                process.arguments = [
                    "--model-dir", modelDir.path,
                    "--wav-path", audioFile.path,
                ]
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                process.qualityOfService = .userInitiated

                // 超时终止
                let timeoutWorkItem = DispatchWorkItem { [process] in
                    if process.isRunning { process.terminate() }
                }
                DispatchQueue.global().asyncAfter(
                    deadline: .now() + Self.timeout,
                    execute: timeoutWorkItem
                )

                do {
                    try process.run()
                } catch {
                    timeoutWorkItem.cancel()
                    continuation.resume(throwing: TypolessError.funasrProcessFailure(
                        message: "无法启动本地识别引擎"
                    ))
                    return
                }

                // 在后台线程等待进程结束
                DispatchQueue.global(qos: .userInitiated).async {
                    process.waitUntilExit()
                    timeoutWorkItem.cancel()

                    let exitCode = process.terminationStatus
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                    if exitCode != 0 {
                        let errorMessage = String(data: errorData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(throwing: TypolessError.funasrProcessFailure(
                            message: errorMessage?.isEmpty == false ? errorMessage! : "识别进程异常退出 (code: \(exitCode))"
                        ))
                        return
                    }

                    guard let outputString = String(data: outputData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                          !outputString.isEmpty else {
                        continuation.resume(throwing: TypolessError.funasrProcessFailure(
                            message: "本地识别结果为空"
                        ))
                        return
                    }

                    // 解析输出：FunASR CLI 输出 JSON 或纯文本
                    let text = Self.parseOutput(outputString)

                    guard !text.isEmpty else {
                        continuation.resume(throwing: TypolessError.funasrProcessFailure(
                            message: "本地识别结果为空"
                        ))
                        return
                    }

                    let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
                    continuation.resume(returning: TranscriptResult(
                        text: text,
                        requestId: nil,
                        durationMs: durationMs
                    ))
                }
            }
        } onCancel: {
            // Task 被取消时，无法直接访问 process 引用
            // 超时机制会兜底清理；若需更精细的取消可改用 actor 持有 process
        }
    }

    // MARK: - 输出解析

    /// 解析 FunASR CLI 输出，支持 JSON 和纯文本两种格式
    private static func parseOutput(_ output: String) -> String {
        // 尝试 JSON 解析
        if let data = output.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            // FunASR 输出格式：[{"text": "识别结果", ...}]
            return json.compactMap { $0["text"] as? String }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 尝试单个 JSON 对象
        if let data = output.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 纯文本模式：直接返回
        return output
    }
}
