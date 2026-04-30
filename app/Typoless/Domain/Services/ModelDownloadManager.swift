import Foundation
import os.log

/// 本地 FunASR 模型下载管理器
///
/// 负责模型下载、进度报告、失败重试、完整性校验与删除。
/// 下载任务绑定应用进程生命周期，退出即中断。
@MainActor
@Observable
final class ModelDownloadManager {

    private struct RemoteModelFile {
        let name: String
        let path: String
        let size: Int64?
    }

    private(set) var progress: Double = 0
    private(set) var isDownloading: Bool = false
    private(set) var lastError: String?

    private let logger = Logger(subsystem: "com.isecret.typoless", category: "ModelDownload")
    private var downloadTask: Task<Void, Never>?
    private weak var configStore: ConfigStore?
    private var downloadedBytes: Int64 = 0
    private var totalBytesExpected: Int64 = 0
    private var currentFileExpectedBytes: Int64 = 0

    /// 固定模型下载列表
    private static let models: [(name: String, repoId: String)] = [
        ("paraformer-zh", "iic/speech_seaco_paraformer_large_asr_nat-zh-cn-16k-common-vocab8404-pytorch"),
        ("fsmn-vad", "iic/speech_fsmn_vad_zh-cn-16k-common-pytorch"),
    ]

    init(configStore: ConfigStore) {
        self.configStore = configStore
    }

    // MARK: - Public API

    /// 开始下载模型
    func startDownload() {
        guard !isDownloading else { return }

        isDownloading = true
        progress = 0
        lastError = nil
        downloadedBytes = 0
        totalBytesExpected = 0
        currentFileExpectedBytes = 0
        try? configStore?.updateLocalModelStatus(.downloading)

        downloadTask = Task { [weak self] in
            await self?.performDownload()
        }
    }

    /// 取消正在进行的下载
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        progress = 0
        downloadedBytes = 0
        totalBytesExpected = 0
        currentFileExpectedBytes = 0
        removeIncompleteModels()
        try? configStore?.updateLocalModelStatus(.notDownloaded)
    }

    /// 重新下载（先删除再下载）
    func redownload() {
        deleteModels()
        startDownload()
    }

    /// 删除已下载的模型
    func deleteModels() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        progress = 0
        downloadedBytes = 0
        totalBytesExpected = 0
        currentFileExpectedBytes = 0

        removeIncompleteModels()

        try? configStore?.updateLocalModelStatus(.notDownloaded)
        logger.info("Models deleted")
    }

    /// 校验本地模型是否就绪
    func validateModels() -> Bool {
        let modelRoot = LocalASRConfig.modelRoot
        let fm = FileManager.default

        for model in Self.models {
            let modelDir = modelRoot.appendingPathComponent(model.name)
            if !fm.fileExists(atPath: modelDir.path) {
                return false
            }
            // 检查模型目录不为空
            guard let contents = try? fm.contentsOfDirectory(atPath: modelDir.path),
                  !contents.isEmpty else {
                return false
            }
        }
        return true
    }

    // MARK: - Download Logic

    private func performDownload() async {
        let modelRoot = LocalASRConfig.modelRoot
        let fm = FileManager.default

        // 确保目录存在
        do {
            try fm.createDirectory(at: modelRoot, withIntermediateDirectories: true)
        } catch {
            await handleDownloadFailure("无法创建模型目录：\(error.localizedDescription)")
            return
        }

        // 读取可选镜像源
        let mirrorSource = configStore?.asrConfig.local.mirrorSource

        let totalModels = Double(Self.models.count)
        var pendingDownloads: [(model: (name: String, repoId: String), destination: URL, files: [RemoteModelFile])] = []

        for (index, model) in Self.models.enumerated() {
            guard !Task.isCancelled else { return }

            let modelDir = modelRoot.appendingPathComponent(model.name)

            // 跳过已存在的模型
            if fm.fileExists(atPath: modelDir.path),
               let contents = try? fm.contentsOfDirectory(atPath: modelDir.path),
               !contents.isEmpty {
                progress = Double(index + 1) / totalModels
                continue
            }

            logger.info("Downloading model: \(model.name, privacy: .public)")

            if let files = try? await fetchRemoteFileList(repoId: model.repoId, mirrorSource: mirrorSource),
               !files.isEmpty {
                pendingDownloads.append((model, modelDir, files))
            } else {
                logger.info("Falling back to git clone for model: \(model.name, privacy: .public)")
                pendingDownloads.append((model, modelDir, []))
            }
        }

        totalBytesExpected = pendingDownloads
            .flatMap(\.files)
            .compactMap(\.size)
            .reduce(0, +)

        for (index, item) in pendingDownloads.enumerated() {
            guard !Task.isCancelled else { return }

            do {
                try await downloadModel(
                    repoId: item.model.repoId,
                    destination: item.destination,
                    mirrorSource: mirrorSource,
                    files: item.files
                )
            } catch {
                guard !Task.isCancelled else { return }
                await handleDownloadFailure("下载 \(item.model.name) 失败：\(error.localizedDescription)")
                return
            }

            progress = Double(index + 1) / totalModels
        }

        guard !Task.isCancelled else { return }

        // 最终校验
        if validateModels() {
            isDownloading = false
            progress = 1.0
            try? configStore?.updateLocalModelStatus(.ready)
            logger.info("All models downloaded and validated")
        } else {
            await handleDownloadFailure("模型校验失败，文件可能不完整")
        }
    }

    private func downloadModel(
        repoId: String,
        destination: URL,
        mirrorSource: String?,
        files: [RemoteModelFile]
    ) async throws {
        let baseURL = mirrorSource ?? "https://modelscope.cn"
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        guard !files.isEmpty else {
            try await downloadViaGitLFS(repoId: repoId, destination: destination, baseURL: baseURL)
            return
        }

        for file in files {
            guard !Task.isCancelled else { throw CancellationError() }

            let downloadURL = "\(baseURL)/api/v1/models/\(repoId)/repo?Revision=master&FilePath=\(file.path)"
            guard let fileURL = URL(string: downloadURL) else { continue }

            let destFile = destination.appendingPathComponent(file.name)

            // 确保父目录存在
            try fm.createDirectory(at: destFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await downloadFile(
                from: fileURL,
                to: destFile,
                expectedSize: file.size
            )
        }
    }

    private func fetchRemoteFileList(
        repoId: String,
        mirrorSource: String?
    ) async throws -> [RemoteModelFile] {
        let baseURL = mirrorSource ?? "https://modelscope.cn"
        let snapshotURL = "\(baseURL)/api/v1/models/\(repoId)/repo/files"

        guard let url = URL(string: snapshotURL) else {
            throw NSError(domain: "ModelDownload", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的下载 URL"])
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "ModelDownload", code: -2, userInfo: [NSLocalizedDescriptionKey: "无法获取模型文件列表"])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["Data"] as? [String: Any],
              let fileList = payload["Files"] as? [[String: Any]] else {
            throw NSError(domain: "ModelDownload", code: -3, userInfo: [NSLocalizedDescriptionKey: "模型文件列表格式异常"])
        }

        return fileList.compactMap { file in
            guard let fileName = file["Name"] as? String,
                  let filePath = file["Path"] as? String else { return nil }

            let sizeValue = file["Size"] ?? file["size"]
            let size: Int64?
            switch sizeValue {
            case let int as Int:
                size = Int64(int)
            case let int64 as Int64:
                size = int64
            case let double as Double:
                size = Int64(double)
            case let string as String:
                size = Int64(string)
            default:
                size = nil
            }

            return RemoteModelFile(name: fileName, path: filePath, size: size)
        }
    }

    private func downloadFile(
        from remoteURL: URL,
        to destinationURL: URL,
        expectedSize: Int64?
    ) async throws {
        currentFileExpectedBytes = max(expectedSize ?? 0, 0)
        let progressReporter = DownloadProgressReporter()
        let session = URLSession(
            configuration: .default,
            delegate: progressReporter,
            delegateQueue: nil
        )
        defer {
            session.invalidateAndCancel()
        }

        let tempURL = try await withTaskCancellationHandler {
            try await progressReporter.download(
                from: remoteURL,
                using: session
            ) { [weak self] written, total in
                Task { @MainActor [weak self] in
                    self?.updateProgress(
                        bytesWritten: written,
                        totalBytesExpectedForFile: total,
                        fallbackExpectedSize: expectedSize
                    )
                }
            }
        } onCancel: {
            progressReporter.cancel()
            session.invalidateAndCancel()
        }

        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        finalizeProgressForFile(destinationURL: destinationURL)
    }

    private func updateProgress(
        bytesWritten: Int64,
        totalBytesExpectedForFile: Int64,
        fallbackExpectedSize: Int64?
    ) {
        let resolvedExpected = totalBytesExpectedForFile > 0 ? totalBytesExpectedForFile : (fallbackExpectedSize ?? 0)
        let expectedForFile = max(resolvedExpected, 0)
        if expectedForFile > currentFileExpectedBytes {
            totalBytesExpected += expectedForFile - currentFileExpectedBytes
            currentFileExpectedBytes = expectedForFile
        }
        guard totalBytesExpected > 0, currentFileExpectedBytes > 0 else { return }

        let clampedWritten = min(max(bytesWritten, 0), currentFileExpectedBytes)
        let aggregate = downloadedBytes + clampedWritten
        progress = min(Double(aggregate) / Double(totalBytesExpected), 0.999)
    }

    private func finalizeProgressForFile(destinationURL: URL) {
        let fallbackSize = (try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let finalizedBytes = max(currentFileExpectedBytes, fallbackSize)
        guard finalizedBytes > 0 else { return }

        if finalizedBytes > currentFileExpectedBytes {
            totalBytesExpected += finalizedBytes - currentFileExpectedBytes
        }

        downloadedBytes += finalizedBytes
        currentFileExpectedBytes = 0
        if totalBytesExpected > 0 {
            progress = min(Double(downloadedBytes) / Double(totalBytesExpected), 0.999)
        }
    }

    private func downloadViaGitLFS(repoId: String, destination: URL, baseURL: String) async throws {
        // Fallback: 使用 git clone（需要 git-lfs）
        let cloneURL = "\(baseURL)/\(repoId).git"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["clone", "--depth", "1", cloneURL, destination.path]
        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "ModelDownload", code: Int(process.terminationStatus),
                         userInfo: [NSLocalizedDescriptionKey: "git clone 失败: \(output.prefix(200))"])
        }

        // 清理 .git 目录
        try? FileManager.default.removeItem(at: destination.appendingPathComponent(".git"))
    }

    private func handleDownloadFailure(_ message: String) async {
        isDownloading = false
        lastError = message
        currentFileExpectedBytes = 0
        try? configStore?.updateLocalModelStatus(.failed, error: message)
        logger.error("Download failed: \(message, privacy: .public)")
    }

    private func removeIncompleteModels() {
        let modelRoot = LocalASRConfig.modelRoot
        try? FileManager.default.removeItem(at: modelRoot)
    }
}

private final class DownloadProgressReporter: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<URL, Error>?
    private var progressHandler: (@Sendable (Int64, Int64) -> Void)?
    private weak var activeTask: URLSessionDownloadTask?

    func download(
        from remoteURL: URL,
        using session: URLSession,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URL {
        progressHandler = progress
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let task = session.downloadTask(with: remoteURL)
            activeTask = task
            task.resume()
        }
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        continuation?.resume(throwing: CancellationError())
        continuation = nil
        progressHandler = nil
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        progressHandler?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        activeTask = nil
        continuation?.resume(returning: location)
        continuation = nil
        progressHandler = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        activeTask = nil
        guard let error else { return }
        continuation?.resume(throwing: error)
        continuation = nil
        progressHandler = nil
    }
}
