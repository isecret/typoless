import Foundation
import os.log

/// Python sidecar 进程生命周期管理器
///
/// 负责 FunASR worker 的启动、停止、健康检查与异常恢复。
/// 首次录音时惰性启动 sidecar，启动后保持常驻，后续请求复用同一进程。
final class ASRRuntimeManager: @unchecked Sendable {

    private let logger = Logger(subsystem: "com.isecret.typoless", category: "ASRRuntime")

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private let lock = NSLock()

    private let resourceRoot: URL
    private let pythonPath: String
    private let workerEntry: String

    /// 初始化，传入 FunASR 资源根目录
    init(resourceRoot: URL? = nil) {
        let root = resourceRoot ?? Self.defaultResourceRoot()
        self.resourceRoot = root

        // Python runtime 查找顺序：内嵌 > 环境变量 > 系统
        let embeddedPython = root.appendingPathComponent("runtime/python3").path
        if FileManager.default.isExecutableFile(atPath: embeddedPython) {
            self.pythonPath = embeddedPython
        } else if let envPython = ProcessInfo.processInfo.environment["FUNASR_PYTHON_PATH"],
                  FileManager.default.isExecutableFile(atPath: envPython) {
            self.pythonPath = envPython
        } else {
            self.pythonPath = "/usr/bin/python3"
        }

        self.workerEntry = root.appendingPathComponent("worker/funasr_worker.py").path
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    /// 启动 sidecar 进程
    func start() throws {
        lock.lock()
        defer { lock.unlock() }

        guard process == nil || !(process?.isRunning ?? false) else { return }

        guard FileManager.default.fileExists(atPath: workerEntry) else {
            throw TypolessError.asrBinaryNotFound
        }
        guard FileManager.default.isExecutableFile(atPath: pythonPath) else {
            throw TypolessError.asrRuntimeMissing
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pythonPath)
        proc.arguments = ["-u", workerEntry]  // unbuffered
        proc.environment = [
            "FUNASR_RESOURCE_PATH": resourceRoot.path,
            "PYTHONUNBUFFERED": "1",
        ]

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        // Drain stderr asynchronously to prevent backpressure
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let line = String(data: data, encoding: .utf8) {
                self?.logger.debug("worker stderr: \(line, privacy: .public)")
            }
        }

        try proc.run()

        self.process = proc
        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.stderrPipe = stderr

        logger.info("FunASR worker started (pid=\(proc.processIdentifier))")
    }

    /// 停止 sidecar 进程
    func stop() {
        lock.lock()
        defer { lock.unlock() }

        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        if let proc = process, proc.isRunning {
            stdinPipe?.fileHandleForWriting.closeFile()
            proc.terminate()
            proc.waitUntilExit()
            logger.info("FunASR worker stopped")
        }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
    }

    /// 发送 JSON-RPC 请求并等待响应
    func sendRequest(_ request: [String: Any]) async throws -> [String: Any] {
        // 确保进程正在运行
        if process == nil || !(process?.isRunning ?? false) {
            try start()
        }

        guard let stdinPipe = stdinPipe,
              let stdoutPipe = stdoutPipe else {
            throw TypolessError.asrRuntimeMissing
        }

        // 序列化请求
        let data = try JSONSerialization.data(withJSONObject: request)
        var line = data
        line.append(contentsOf: "\n".utf8)

        // 写入 stdin
        let writeHandle = stdinPipe.fileHandleForWriting
        try writeHandle.write(contentsOf: line)

        // 从 stdout 读取一行响应
        let responseData = try await readLine(from: stdoutPipe.fileHandleForReading)

        guard let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw TypolessError.asrProcessFailure(message: "Invalid JSON-RPC response")
        }

        // 检查 JSON-RPC 错误
        if let error = response["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Unknown worker error"
            throw TypolessError.asrProcessFailure(message: message)
        }

        return response
    }

    /// 健康检查
    func ping() async throws {
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "ping",
            "id": 0,
        ]
        _ = try await sendRequest(request)
    }

    /// 强制重启 sidecar
    func restart() throws {
        stop()
        try start()
    }

    /// 检查 sidecar 是否正在运行
    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process?.isRunning ?? false
    }

    // MARK: - Private

    private func readLine(from handle: FileHandle) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var buffer = Data()
                while true {
                    let byte = handle.readData(ofLength: 1)
                    if byte.isEmpty {
                        // EOF
                        if buffer.isEmpty {
                            continuation.resume(throwing: TypolessError.asrProcessFailure(message: "Worker process terminated unexpectedly"))
                        } else {
                            continuation.resume(returning: buffer)
                        }
                        return
                    }
                    if byte[0] == UInt8(ascii: "\n") {
                        continuation.resume(returning: buffer)
                        return
                    }
                    buffer.append(byte)
                }
            }
        }
    }

    private static func defaultResourceRoot() -> URL {
        // 优先使用环境变量
        if let envPath = ProcessInfo.processInfo.environment["FUNASR_RESOURCE_PATH"] {
            return URL(fileURLWithPath: envPath)
        }
        // 从 App bundle 定位
        return Bundle.main.resourceURL!.appendingPathComponent("funasr")
    }
}
