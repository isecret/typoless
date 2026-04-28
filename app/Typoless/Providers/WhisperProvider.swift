import Foundation

/// 本地 Whisper 语音识别 Provider，通过内置 whisper-cli 子进程执行离线识别
struct WhisperProvider: ASRProvider, Sendable {

    private static let timeout: TimeInterval = 60

    // MARK: - 资源路径

    private static var binaryURL: URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("whisper")
            .appendingPathComponent("bin")
            .appendingPathComponent("whisper-cli")
    }

    private static var modelFileURL: URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("whisper")
            .appendingPathComponent("models")
            .appendingPathComponent("ggml-small.bin")
    }

    // MARK: - ASRProvider

    func recognize(audioData: Data) async throws -> TranscriptResult {
        guard let binaryURL = Self.binaryURL,
              FileManager.default.fileExists(atPath: binaryURL.path) else {
            throw TypolessError.asrBinaryNotFound
        }

        guard let modelURL = Self.modelFileURL,
              FileManager.default.fileExists(atPath: modelURL.path) else {
            throw TypolessError.asrModelMissing
        }

        // 校验模型文件非空
        let attrs = try? FileManager.default.attributesOfItem(atPath: modelURL.path)
        guard let fileSize = attrs?[.size] as? UInt64, fileSize > 0 else {
            throw TypolessError.asrModelMissing
        }

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("typoless_\(UUID().uuidString).wav")

        defer { try? FileManager.default.removeItem(at: tempFile) }

        do {
            try audioData.write(to: tempFile)
        } catch {
            throw TypolessError.asrProcessFailure(message: "无法写入临时音频文件")
        }

        return try await runProcess(
            binary: binaryURL,
            model: modelURL,
            audioFile: tempFile
        )
    }

    // MARK: - 子进程执行

    /// 在非主线程执行子进程，支持 Task 取消时终止进程
    private func runProcess(
        binary: URL,
        model: URL,
        audioFile: URL
    ) async throws -> TranscriptResult {
        let startTime = Date()
        let processHolder = ProcessHolder()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                let outputPipe = Pipe()
                let errorPipe = Pipe()

                process.executableURL = binary
                process.arguments = [
                    "-m", model.path,
                    "-f", audioFile.path,
                    "-l", "zh",
                    "-nt",
                    "-np",
                ]
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                process.qualityOfService = .userInitiated

                processHolder.process = process

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
                    continuation.resume(throwing: TypolessError.asrProcessFailure(
                        message: "无法启动本地识别引擎"
                    ))
                    return
                }

                DispatchQueue.global(qos: .userInitiated).async {
                    process.waitUntilExit()
                    timeoutWorkItem.cancel()

                    let exitCode = process.terminationStatus
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                    if exitCode != 0 {
                        let errorMessage = String(data: errorData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(throwing: TypolessError.asrProcessFailure(
                            message: errorMessage?.isEmpty == false ? errorMessage! : "识别进程异常退出 (code: \(exitCode))"
                        ))
                        return
                    }

                    guard let outputString = String(data: outputData, encoding: .utf8) else {
                        continuation.resume(throwing: TypolessError.asrProcessFailure(
                            message: "本地识别结果为空"
                        ))
                        return
                    }

                    let text = Self.normalizeOutput(outputString)

                    guard !text.isEmpty else {
                        continuation.resume(throwing: TypolessError.asrProcessFailure(
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
            processHolder.terminate()
        }
    }

    // MARK: - 输出解析

    /// 规范化 whisper-cli 输出：拆行、去空、合并
    private static func normalizeOutput(_ output: String) -> String {
        output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined()
    }
}

// MARK: - Process Holder

/// 持有 Process 引用以支持 Task 取消时终止子进程
private final class ProcessHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var _process: Process?

    var process: Process? {
        get { lock.withLock { _process } }
        set { lock.withLock { _process = newValue } }
    }

    func terminate() {
        lock.withLock {
            if let p = _process, p.isRunning {
                p.terminate()
            }
        }
    }
}
