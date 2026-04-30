import Foundation
import os.log

/// Python sidecar 进程生命周期管理器
///
/// 负责 FunASR worker 的启动、停止、预热、健康检查与异常恢复。
/// 支持录音开始即后台预热（单飞）、串行 RPC 通道、自适应空闲保活。
final class ASRRuntimeManager: @unchecked Sendable {

    /// 空闲保活策略
    enum IdlePolicy: Sendable {
        case warmupOnly         // 仅预热后空闲：90 秒
        case afterRecognition   // 识别成功后空闲：180 秒

        var timeout: TimeInterval {
            switch self {
            case .warmupOnly: return 90
            case .afterRecognition: return 180
            }
        }
    }

    /// 预热状态
    enum WarmupState: Sendable {
        case cold       // 未启动 / 已释放
        case warming    // 正在预热中
        case warm       // 已加载模型，可直接识别
    }

    private(set) var warmupState: WarmupState = .cold

    private let logger = Logger(subsystem: "com.isecret.typoless", category: "ASRRuntime")

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private let lock = NSLock()
    private var activeRequestCount = 0
    private var idleShutdownTask: Task<Void, Never>?
    private var currentIdlePolicy: IdlePolicy = .warmupOnly

    /// 单飞预热任务
    private var warmupTask: Task<Void, Error>?

    /// 串行 RPC 队列，防止并发读写 stdio 导致响应串线
    private let rpcQueue = DispatchQueue(label: "com.isecret.typoless.asr-rpc", qos: .userInitiated)
    private let rpcSemaphore = DispatchSemaphore(value: 1)

    private let resourceRoot: URL
    private let pythonPath: String
    private let workerEntry: String

    /// 初始化，传入 FunASR 资源根目录
    init(resourceRoot: URL? = nil) {
        let root = resourceRoot ?? Self.defaultResourceRoot()
        self.resourceRoot = root

        self.pythonPath = Self.resolvePythonPath(resourceRoot: root)

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

        cancelIdleShutdownLocked(reason: "worker start requested")
        try startLocked()
    }

    /// 停止 sidecar 进程
    func stop() {
        lock.lock()
        defer { lock.unlock() }

        warmupTask?.cancel()
        warmupTask = nil
        warmupState = .cold
        stopLocked(reason: "explicit stop")
    }

    // MARK: - Warmup（单飞预热）

    /// 触发后台预热。如果已 warm 则立即返回；如果正在 warming 则复用同一 task。
    /// 预热不阻塞调用方，调用方可在需要时 await 返回的 task。
    @discardableResult
    func warmup() -> Task<Void, Error> {
        lock.lock()
        defer { lock.unlock() }

        cancelIdleShutdownLocked(reason: "warmup requested")

        if warmupState == .warm, process?.isRunning == true {
            return Task { }
        }

        if let existing = warmupTask {
            return existing
        }

        let task = Task { [weak self] in
            guard let self else { return }
            try await self.performWarmup()
        }
        warmupTask = task
        warmupState = .warming

        logger.info("FunASR warmup started")
        return task
    }

    /// 等待预热完成（如果正在进行）。已 warm 或 cold 状态不阻塞。
    func awaitWarmupIfNeeded() async throws {
        let task = lock.withLock { warmupTask }

        if let task {
            try await task.value
        }
    }

    private func performWarmup() async throws {
        // 启动 worker 进程
        do {
            try lock.withLock { try startLocked() }
        } catch {
            lock.withLock {
                warmupState = .cold
                warmupTask = nil
            }
            throw error
        }

        // 发送 warmup RPC（触发模型加载）
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "warmup",
            "id": 0,
        ]
        do {
            _ = try await sendRequest(request)
        } catch {
            // warmup 失败不阻塞后续 recognize（recognize 会自行重试启动）
            lock.withLock {
                warmupState = .cold
                warmupTask = nil
            }
            logger.warning("FunASR warmup failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        lock.withLock {
            warmupState = .warm
            warmupTask = nil
            currentIdlePolicy = .warmupOnly
            scheduleIdleShutdownLocked()
        }

        logger.info("FunASR warmup completed | idle_policy=warmupOnly")
    }

    // MARK: - RPC

    /// 发送 JSON-RPC 请求并等待响应（串行化）
    func sendRequest(_ request: [String: Any]) async throws -> [String: Any] {
        let requestData = try JSONSerialization.data(withJSONObject: request)
        let responseData = try await sendRequestData(requestData)

        guard let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw TypolessError.asrProcessFailure(message: "Invalid JSON-RPC response")
        }

        if let error = response["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Unknown worker error"
            throw TypolessError.asrProcessFailure(message: message)
        }

        return response
    }

    /// 发送已编码的 JSON-RPC 请求并返回原始响应数据（串行化，防止并发读写）
    func sendRequestData(_ requestData: Data) async throws -> Data {
        let (writeHandle, readHandle) = try prepareRequestHandles()
        defer { finishRequest() }

        var requestLine = requestData
        requestLine.append(contentsOf: "\n".utf8)

        // 串行化 RPC：等待信号量确保同一时间只有一个请求在读写 stdio
        return try await withCheckedThrowingContinuation { continuation in
            rpcQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: TypolessError.asrProcessFailure(message: "Runtime deallocated"))
                    return
                }
                self.rpcSemaphore.wait()
                defer { self.rpcSemaphore.signal() }

                do {
                    try writeHandle.write(contentsOf: requestLine)
                } catch {
                    continuation.resume(throwing: TypolessError.asrProcessFailure(message: "Failed to write to worker: \(error.localizedDescription)"))
                    return
                }

                var buffer = Data()
                while true {
                    let byte = readHandle.readData(ofLength: 1)
                    if byte.isEmpty {
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

    /// 标记识别成功，延长保活时间
    func markRecognitionSucceeded() {
        lock.lock()
        defer { lock.unlock() }
        currentIdlePolicy = .afterRecognition
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
        lock.lock()
        defer { lock.unlock() }

        warmupTask?.cancel()
        warmupTask = nil
        warmupState = .cold
        stopLocked(reason: "worker restart requested")
        try startLocked()
    }

    /// 检查 sidecar 是否正在运行
    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process?.isRunning ?? false
    }

    // MARK: - Diagnostics

    /// 当前诊断信息快照
    struct DiagnosticsSnapshot: Sendable {
        let isColdStart: Bool
        let warmupState: WarmupState
        let workerReused: Bool
        let idlePolicy: IdlePolicy
    }

    /// 获取当前诊断快照
    func diagnosticsSnapshot(wasColdStart: Bool) -> DiagnosticsSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return DiagnosticsSnapshot(
            isColdStart: wasColdStart,
            warmupState: warmupState,
            workerReused: process?.isRunning ?? false,
            idlePolicy: currentIdlePolicy
        )
    }

    // MARK: - Private

    private func prepareRequestHandles() throws -> (FileHandle, FileHandle) {
        lock.lock()
        defer { lock.unlock() }

        cancelIdleShutdownLocked(reason: "new ASR request")
        try startLocked()

        guard let stdinPipe,
              let stdoutPipe else {
            throw TypolessError.asrRuntimeMissing
        }

        activeRequestCount += 1
        return (stdinPipe.fileHandleForWriting, stdoutPipe.fileHandleForReading)
    }

    private func finishRequest() {
        lock.lock()
        defer { lock.unlock() }

        activeRequestCount = max(0, activeRequestCount - 1)
        scheduleIdleShutdownLocked()
    }

    private func startLocked() throws {
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
            "FUNASR_MODEL_ROOT": LocalASRConfig.modelRoot.path,
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

        process = proc
        stdinPipe = stdin
        stdoutPipe = stdout
        stderrPipe = stderr

        logger.info("FunASR worker started (pid=\(proc.processIdentifier))")
    }

    private func stopLocked(reason: String) {
        cancelIdleShutdownLocked(reason: reason)
        activeRequestCount = 0
        warmupState = .cold
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        if let proc = process, proc.isRunning {
            stdinPipe?.fileHandleForWriting.closeFile()
            proc.terminate()
            proc.waitUntilExit()
            logger.info("FunASR worker stopped | reason=\(reason, privacy: .public)")
        }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
    }

    private func scheduleIdleShutdownLocked() {
        guard activeRequestCount == 0 else { return }

        idleShutdownTask?.cancel()
        let timeout = currentIdlePolicy.timeout
        logger.info("FunASR idle shutdown scheduled | timeout=\(Int(timeout))s policy=\(String(describing: self.currentIdlePolicy), privacy: .public)")

        idleShutdownTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            self?.triggerIdleShutdown()
        }
    }

    private func cancelIdleShutdownLocked(reason: String) {
        guard let idleShutdownTask else { return }
        idleShutdownTask.cancel()
        self.idleShutdownTask = nil
        logger.debug("FunASR idle shutdown cancelled | reason=\(reason, privacy: .public)")
    }

    private func triggerIdleShutdown() {
        lock.lock()
        defer { lock.unlock() }

        idleShutdownTask = nil

        guard activeRequestCount == 0 else { return }
        guard process?.isRunning == true else { return }

        stopLocked(reason: "idle timeout")
    }

    static func defaultResourceRoot() -> URL {
        // 优先使用环境变量
        if let envPath = ProcessInfo.processInfo.environment["FUNASR_RESOURCE_PATH"] {
            return URL(fileURLWithPath: envPath)
        }
        // 从 App bundle 定位
        return Bundle.main.resourceURL!.appendingPathComponent("funasr")
    }

    private static func resolvePythonPath(resourceRoot: URL) -> String {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let env = ProcessInfo.processInfo.environment

        let candidates: [String?] = [
            resourceRoot.appendingPathComponent("runtime/python3").path,
            env["FUNASR_PYTHON_PATH"],
            "\(home)/.pyenv/shims/python3",
            env["PYENV_ROOT"].map { "\($0)/shims/python3" },
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]

        return candidates
            .compactMap { $0 }
            .first(where: { fm.isExecutableFile(atPath: $0) })
            ?? "/usr/bin/python3"
    }
}
