import Foundation
import os.log

/// 本地 SenseVoice 模型下载管理器
///
/// 负责模型下载、进度报告、失败重试、完整性校验与删除。
/// 下载任务绑定应用进程生命周期，退出即中断。
@MainActor
@Observable
final class ModelDownloadManager {

    private struct RemoteModelFile {
        let name: String
        let urlPath: String
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

    /// 固定模型下载列表。文件来自 sherpa-onnx 维护的 SenseVoice ONNX 包。
    private static let modelFiles: [RemoteModelFile] = [
        RemoteModelFile(
            name: LocalASRConfig.modelFileName,
            urlPath: "model.int8.onnx",
            size: nil
        ),
        RemoteModelFile(
            name: LocalASRConfig.tokensFileName,
            urlPath: "tokens.txt",
            size: nil
        ),
    ]

    private static let defaultModelBaseURL = "https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main"

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

        for fileName in LocalASRConfig.requiredFileNames {
            let fileURL = modelRoot.appendingPathComponent(fileName)
            guard fm.fileExists(atPath: fileURL.path),
                  ((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0 else {
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

        let baseURL = configStore?.asrConfig.local.mirrorSource ?? Self.defaultModelBaseURL
        let totalFiles = Double(Self.modelFiles.count)
        totalBytesExpected = Self.modelFiles.compactMap(\.size).reduce(0, +)

        for (index, file) in Self.modelFiles.enumerated() {
            guard !Task.isCancelled else { return }

            let destination = modelRoot.appendingPathComponent(file.name)

            if fm.fileExists(atPath: destination.path),
               ((try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0 {
                progress = Double(index + 1) / totalFiles
                continue
            }

            logger.info("Downloading SenseVoice model file: \(file.name, privacy: .public)")
            do {
                try await downloadFile(
                    from: try modelFileURL(baseURL: baseURL, file: file),
                    to: destination,
                    expectedSize: file.size
                )
            } catch {
                guard !Task.isCancelled else { return }
                await handleDownloadFailure("下载 \(file.name) 失败：\(error.localizedDescription)")
                return
            }

            progress = Double(index + 1) / totalFiles
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

    private func modelFileURL(baseURL: String, file: RemoteModelFile) throws -> URL {
        let normalizedBase = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: "\(normalizedBase)/\(file.urlPath)") else {
            throw NSError(domain: "ModelDownload", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的下载 URL"])
        }
        return url
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
            session.finishTasksAndInvalidate()
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
    private let fileManager = FileManager.default

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
        do {
            let preservedURL = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            if fileManager.fileExists(atPath: preservedURL.path) {
                try fileManager.removeItem(at: preservedURL)
            }
            try fileManager.moveItem(at: location, to: preservedURL)
            continuation?.resume(returning: preservedURL)
        } catch {
            continuation?.resume(throwing: error)
        }
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
