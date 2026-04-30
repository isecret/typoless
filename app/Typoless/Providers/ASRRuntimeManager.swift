import Foundation
import os.log

/// Python sidecar 进程生命周期管理器
///
/// 负责 FunASR worker 的启动、停止、预热、健康检查与异常恢复。
/// 支持录音开始即后台预热（单飞）、串行 RPC 通道、自适应空闲保活。
///
/// 安全约束：
/// - 同一时间只允许一个 RPC 请求在飞
/// - 超时、取消、非法响应或 ID 不匹配时标记 worker 为 contaminated 并销毁
/// - 所有状态变更通过 processGeneration 防止旧回调污染新 worker
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

    /// Worker 运行状态
    private enum RuntimeState {
        case idle       // 无 worker 进程
        case running    // worker 正常运行
        case stopping   // 正在终止 worker（阻止新请求）
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
    private var runtimeState: RuntimeState = .idle

    /// 进程代数：每次启动新 worker 递增，用于防止旧回调污染新 worker
    private var processGeneration: UInt64 = 0

    /// 全局递增的 RPC 请求 ID，由 runtime 统一分配
    private var nextRequestID: Int = 1

    /// 单飞预热任务
    private var warmupTask: Task<Void, Error>?

    /// 串行 RPC 队列，防止并发读写 stdio 导致响应串线
    private let rpcQueue = DispatchQueue(label: "com.isecret.typoless.asr-rpc", qos: .userInitiated)
    private let rpcSemaphore = DispatchSemaphore(value: 1)

    /// Grace period: SIGTERM 后等待退出的最大时间
    private static let terminationGracePeriod: TimeInterval = 3

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

        guard runtimeState != .stopping else {
            throw TypolessError.asrProcessFailure(message: "Worker is shutting down, please retry")
        }

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

    /// 标记当前 worker 为不可信并终止，用于外部取消场景
    func invalidateCurrentWorker() {
        lock.lock()
        defer { lock.unlock() }

        guard runtimeState == .running else { return }
        logger.warning("Worker invalidated by external cancel")
        stopLocked(reason: "external invalidation (cancel)")
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
            try lock.withLock {
                guard runtimeState != .stopping else {
                    throw TypolessError.asrProcessFailure(message: "Worker is shutting down")
                }
                try startLocked()
            }
        } catch {
            lock.withLock {
                warmupState = .cold
                warmupTask = nil
            }
            throw error
        }

        // 发送 warmup RPC（触发模型加载）
        do {
            _ = try await sendRequest(method: "warmup", params: nil, timeout: 30)
        } catch {
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

    // MARK: - RPC (Public API)

    /// 发送 JSON-RPC 请求并等待响应，带超时和完整验证
    ///
    /// - Parameters:
    ///   - method: JSON-RPC method 名称
    ///   - params: 可选请求参数
    ///   - timeout: 超时时间（秒），超时后 worker 被视为 contaminated
    /// - Returns: response 的 "result" 字段
    func sendRequest(
        method: String,
        params: [String: Any]?,
        timeout: TimeInterval
    ) async throws -> [String: Any] {
        let (requestData, requestID) = try buildRequest(method: method, params: params)
        let responseData = try await sendRequestDataWithTimeout(requestData, requestID: requestID, timeout: timeout)
        return try validateResponse(responseData, expectedID: requestID)
    }

    /// 发送已编码的 JSON-RPC 请求并返回原始响应数据（用于自定义请求构建）
    ///
    /// - Parameters:
    ///   - requestData: 已编码的 JSON 请求数据
    ///   - requestID: 此请求的 ID，用于响应验证
    ///   - timeout: 超时时间（秒）
    func sendRequestDataWithTimeout(_ requestData: Data, requestID: Int, timeout: TimeInterval) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { [self] in
                try await self.performRPC(requestData)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw TypolessError.asrProcessFailure(message: "ASR timeout after \(Int(timeout))s")
            }

            do {
                guard let result = try await group.next() else {
                    throw TypolessError.asrProcessFailure(message: "ASR task group empty")
                }
                group.cancelAll()
                return result
            } catch {
                group.cancelAll()
                // 超时或其他错误：标记 worker 为 contaminated
                if case .asrProcessFailure(let msg) = error as? TypolessError, msg.contains("timeout") {
                    markContaminatedAndStop(reason: "RPC timeout (id=\(requestID))")
                }
                throw error
            }
        }
    }

    /// 构建 JSON-RPC 请求并分配唯一 ID
    func buildRequest(method: String, params: [String: Any]?) throws -> (Data, Int) {
        let reqID = lock.withLock {
            let id = nextRequestID
            nextRequestID += 1
            return id
        }

        var request: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "id": reqID,
        ]
        if let params {
            request["params"] = params
        }

        let data = try JSONSerialization.data(withJSONObject: request)
        return (data, reqID)
    }

    /// 标记识别成功，延长保活时间
    func markRecognitionSucceeded() {
        lock.lock()
        defer { lock.unlock() }
        currentIdlePolicy = .afterRecognition
    }

    /// 健康检查
    func ping() async throws {
        _ = try await sendRequest(method: "ping", params: nil, timeout: 5)
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
        return runtimeState == .running && (process?.isRunning ?? false)
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

    // MARK: - Private: RPC Execution

    /// 执行 RPC 请求（串行化，防止并发读写）
    private func performRPC(_ requestData: Data) async throws -> Data {
        let (writeHandle, readHandle, gen) = try prepareRequestHandles()
        defer { finishRequest() }

        var requestLine = requestData
        requestLine.append(contentsOf: "\n".utf8)

        return try await withCheckedThrowingContinuation { continuation in
            rpcQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: TypolessError.asrProcessFailure(message: "Runtime deallocated"))
                    return
                }

                self.rpcSemaphore.wait()
                defer { self.rpcSemaphore.signal() }

                // 验证 process generation 未变（worker 未被替换）
                let currentGen = self.lock.withLock { self.processGeneration }
                guard currentGen == gen else {
                    continuation.resume(throwing: TypolessError.asrProcessFailure(message: "Worker replaced during request"))
                    return
                }

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

    /// 验证 JSON-RPC 响应的完整性
    private func validateResponse(_ data: Data, expectedID: Int) throws -> [String: Any] {
        let response: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                markContaminatedAndStop(reason: "Non-dict JSON response")
                throw TypolessError.asrProcessFailure(message: "Invalid JSON-RPC response")
            }
            response = parsed
        } catch let error as TypolessError {
            throw error
        } catch {
            let raw = String(data: data, encoding: .utf8)?
                .replacingOccurrences(of: "\n", with: "\\n")
                .prefix(160) ?? "non-utf8"
            logger.error("Failed to parse worker response: \(String(raw), privacy: .public)")
            markContaminatedAndStop(reason: "Unparseable JSON response")
            throw TypolessError.asrProcessFailure(message: "Invalid JSON-RPC response")
        }

        // 验证 response ID
        if let responseID = response["id"] as? Int {
            if responseID != expectedID {
                logger.error("Response ID mismatch: expected=\(expectedID) got=\(responseID)")
                markContaminatedAndStop(reason: "Response ID mismatch (expected=\(expectedID), got=\(responseID))")
                throw TypolessError.asrProcessFailure(message: "Protocol desync: response ID mismatch")
            }
        }

        // 检查 JSON-RPC error
        if let error = response["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Unknown worker error"
            throw TypolessError.asrProcessFailure(message: message)
        }

        return response["result"] as? [String: Any] ?? response
    }

    // MARK: - Private: Worker Lifecycle

    private func prepareRequestHandles() throws -> (FileHandle, FileHandle, UInt64) {
        lock.lock()
        defer { lock.unlock() }

        guard runtimeState != .stopping else {
            throw TypolessError.asrProcessFailure(message: "Worker is shutting down, please retry")
        }

        cancelIdleShutdownLocked(reason: "new ASR request")
        try startLocked()

        guard let stdinPipe,
              let stdoutPipe else {
            throw TypolessError.asrRuntimeMissing
        }

        activeRequestCount += 1
        return (stdinPipe.fileHandleForWriting, stdoutPipe.fileHandleForReading, processGeneration)
    }

    private func finishRequest() {
        lock.lock()
        defer { lock.unlock() }

        activeRequestCount = max(0, activeRequestCount - 1)
        if runtimeState == .running {
            scheduleIdleShutdownLocked()
        }
    }

    private func startLocked() throws {
        guard runtimeState != .running || !(process?.isRunning ?? false) else { return }

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

        processGeneration &+= 1
        let gen = processGeneration

        // 监听 worker 异常退出
        proc.terminationHandler = { [weak self] terminatedProc in
            self?.handleWorkerTermination(terminatedProc, generation: gen)
        }

        try proc.run()

        process = proc
        stdinPipe = stdin
        stdoutPipe = stdout
        stderrPipe = stderr
        runtimeState = .running

        logger.info("FunASR worker started (pid=\(proc.processIdentifier), gen=\(gen))")
    }

    private func stopLocked(reason: String) {
        cancelIdleShutdownLocked(reason: reason)
        activeRequestCount = 0
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        guard let proc = process else {
            runtimeState = .idle
            process = nil
            stdinPipe = nil
            stdoutPipe = nil
            stderrPipe = nil
            return
        }

        runtimeState = .stopping

        if proc.isRunning {
            // 关闭 stdin 通知 worker 退出
            stdinPipe?.fileHandleForWriting.closeFile()
            proc.terminate()

            // Grace period: 等待最多 3 秒
            let deadline = Date().addingTimeInterval(Self.terminationGracePeriod)
            while proc.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }

            // 超过 grace period 仍在运行，强制 kill
            if proc.isRunning {
                kill(proc.processIdentifier, SIGKILL)
                proc.waitUntilExit()
                logger.warning("FunASR worker force-killed | reason=\(reason, privacy: .public)")
            } else {
                logger.info("FunASR worker stopped | reason=\(reason, privacy: .public)")
            }
        }

        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        runtimeState = .idle
    }

    /// 标记 worker 为 contaminated 并异步销毁
    private func markContaminatedAndStop(reason: String) {
        lock.lock()
        defer { lock.unlock() }

        guard runtimeState == .running else { return }
        logger.warning("Worker contaminated: \(reason, privacy: .public)")
        warmupState = .cold
        warmupTask?.cancel()
        warmupTask = nil
        stopLocked(reason: "contaminated: \(reason)")
    }

    /// 处理 worker 异常退出
    private func handleWorkerTermination(_ proc: Process, generation: UInt64) {
        lock.lock()
        defer { lock.unlock() }

        // 只处理当前代的 worker 退出
        guard generation == processGeneration else { return }
        // 如果是 .stopping 状态的正常退出，忽略
        guard runtimeState == .running else { return }

        let status = proc.terminationStatus
        let reason = proc.terminationReason

        logger.warning("FunASR worker exited unexpectedly | status=\(status) reason=\(reason.rawValue) gen=\(generation)")

        // 清理状态，允许下次请求自动重启
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        runtimeState = .idle
        warmupState = .cold
        warmupTask?.cancel()
        warmupTask = nil
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
        guard runtimeState == .running, process?.isRunning == true else { return }

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
