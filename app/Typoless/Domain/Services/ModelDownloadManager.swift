import Foundation
import os.log

/// 本地 FunASR 模型下载管理器
///
/// 负责模型下载、进度报告、失败重试、完整性校验与删除。
/// 下载任务绑定应用进程生命周期，退出即中断。
@MainActor
@Observable
final class ModelDownloadManager {

    private(set) var progress: Double = 0
    private(set) var isDownloading: Bool = false
    private(set) var lastError: String?

    private let logger = Logger(subsystem: "com.isecret.typoless", category: "ModelDownload")
    private var downloadTask: Task<Void, Never>?
    private weak var configStore: ConfigStore?

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
        try? configStore?.updateLocalModelStatus(.notDownloaded, error: "用户取消")
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

        let modelRoot = LocalASRConfig.modelRoot
        try? FileManager.default.removeItem(at: modelRoot)

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

            do {
                try await downloadModel(
                    name: model.name,
                    repoId: model.repoId,
                    destination: modelDir,
                    mirrorSource: mirrorSource
                )
            } catch {
                guard !Task.isCancelled else { return }
                await handleDownloadFailure("下载 \(model.name) 失败：\(error.localizedDescription)")
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
        name: String,
        repoId: String,
        destination: URL,
        mirrorSource: String?
    ) async throws {
        // 构建下载脚本命令：使用 Python modelscope snapshot_download
        let baseURL = mirrorSource ?? "https://modelscope.cn"
        let script = """
        import sys
        sys.path.insert(0, '')
        from modelscope.hub.snapshot_download import snapshot_download
        snapshot_download('\(repoId)', cache_dir='\(destination.deletingLastPathComponent().path)', local_dir='\(destination.path)')
        """

        // 使用简化的 HTTP 下载方式替代 modelscope SDK
        // 直接从 ModelScope 下载模型快照
        let snapshotURL = "\(baseURL)/api/v1/models/\(repoId)/repo/files"

        guard let url = URL(string: snapshotURL) else {
            throw NSError(domain: "ModelDownload", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的下载 URL"])
        }

        // 获取文件列表
        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "ModelDownload", code: -2, userInfo: [NSLocalizedDescriptionKey: "无法获取模型文件列表"])
        }

        // 解析文件列表并下载
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["Data"] as? [String: Any],
              let fileList = files["Files"] as? [[String: Any]] else {
            // 如果 API 格式不匹配，尝试直接用 git clone 方式
            try await downloadViaGitLFS(repoId: repoId, destination: destination, baseURL: baseURL)
            return
        }

        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        for file in fileList {
            guard !Task.isCancelled else { throw CancellationError() }

            guard let fileName = file["Name"] as? String,
                  let filePath = file["Path"] as? String else { continue }

            let downloadURL = "\(baseURL)/api/v1/models/\(repoId)/repo?Revision=master&FilePath=\(filePath)"
            guard let fileURL = URL(string: downloadURL) else { continue }

            let (fileData, _) = try await URLSession.shared.data(from: fileURL)
            let destFile = destination.appendingPathComponent(fileName)

            // 确保父目录存在
            try fm.createDirectory(at: destFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileData.write(to: destFile, options: .atomic)
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
        try? configStore?.updateLocalModelStatus(.failed, error: message)
        logger.error("Download failed: \(message, privacy: .public)")
    }
}
