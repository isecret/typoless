import CryptoKit
import Foundation

@MainActor
@Observable
final class LLMModelListService {
    typealias Fetcher = @Sendable (LLMModelListInput) async throws -> [String]
    typealias NowProvider = () -> ContinuousClock.Instant

    private struct CacheEntry {
        let models: [String]
        let status: LLMModelListStatus
        let loadedAt: ContinuousClock.Instant
        let retryAfter: ContinuousClock.Instant?
        let errorMessage: String?
    }

    private static let defaultCacheTTL: Duration = .seconds(15 * 60)

    private let fetcher: Fetcher
    private let cacheTTL: Duration
    private let now: NowProvider
    private var loadTask: Task<Void, Never>?
    private var activeCacheKey: Data?
    private var activeRequestID: UUID?
    private var cache: [Data: CacheEntry] = [:]

    private(set) var status: LLMModelListStatus = .incomplete
    private(set) var models: [String] = []
    private(set) var lastErrorMessage: String?

    init(
        cacheTTL: Duration = LLMModelListService.defaultCacheTTL,
        now: @escaping NowProvider = { ContinuousClock.now },
        fetcher: Fetcher? = nil
    ) {
        self.cacheTTL = cacheTTL
        self.now = now
        self.fetcher = fetcher ?? Self.makeDefaultFetcher()
    }

    func load(_ input: LLMModelListInput, force: Bool = false) {
        let normalizedInput = input.normalized()

        guard normalizedInput.isComplete else {
            cancelOngoingLoad()
            status = .incomplete
            models = []
            lastErrorMessage = nil
            return
        }

        let cacheKey = Self.cacheKey(for: normalizedInput)
        if activeCacheKey == cacheKey {
            return
        }
        cancelOngoingLoad()

        let currentTime = now()
        let cachedEntry = cache[cacheKey]
        if let cachedEntry {
            models = cachedEntry.models
            status = cachedEntry.status
            lastErrorMessage = cachedEntry.errorMessage

            if !force,
               cachedEntry.status == .unavailable || isFresh(cachedEntry, at: currentTime) {
                return
            }
        } else {
            models = []
            status = .loading
            lastErrorMessage = nil
        }

        let requestID = UUID()
        activeCacheKey = cacheKey
        activeRequestID = requestID

        let fetcher = self.fetcher
        loadTask = Task { [weak self] in
            let result: Result<[String], Error>
            do {
                let models = try await fetcher(normalizedInput)
                result = .success(models)
            } catch {
                result = .failure(error)
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self,
                      self.activeCacheKey == cacheKey,
                      self.activeRequestID == requestID else { return }
                self.activeCacheKey = nil
                self.activeRequestID = nil
                self.loadTask = nil

                switch result {
                case .success(let models):
                    self.cache[cacheKey] = CacheEntry(
                        models: models,
                        status: .loaded,
                        loadedAt: self.now(),
                        retryAfter: nil,
                        errorMessage: nil
                    )
                    self.models = models
                    self.status = .loaded
                    self.lastErrorMessage = nil
                case .failure(let error):
                    let errorMessage = Self.errorMessage(from: error)
                    if let cachedEntry = self.cache[cacheKey] {
                        self.cache[cacheKey] = CacheEntry(
                            models: cachedEntry.models,
                            status: cachedEntry.status,
                            loadedAt: cachedEntry.loadedAt,
                            retryAfter: cachedEntry.status == .loaded
                                ? self.now().advanced(by: self.cacheTTL)
                                : nil,
                            errorMessage: errorMessage
                        )
                        self.models = cachedEntry.models
                        self.status = cachedEntry.status
                    } else {
                        self.cache[cacheKey] = CacheEntry(
                            models: [],
                            status: .unavailable,
                            loadedAt: self.now(),
                            retryAfter: nil,
                            errorMessage: errorMessage
                        )
                        self.models = []
                        self.status = .unavailable
                    }
                    self.lastErrorMessage = errorMessage
                }
            }
        }
    }

    private func cancelOngoingLoad() {
        loadTask?.cancel()
        loadTask = nil
        activeCacheKey = nil
        activeRequestID = nil
    }

    private func isFresh(_ entry: CacheEntry, at currentTime: ContinuousClock.Instant) -> Bool {
        if let retryAfter = entry.retryAfter, currentTime < retryAfter {
            return true
        }
        return currentTime - entry.loadedAt < cacheTTL
    }

    /// 缓存身份只保留不可逆摘要，避免把明文 API Key 作为可输出的字典键。
    private static func cacheKey(for input: LLMModelListInput) -> Data {
        var identity = Data(input.normalizedBaseURL.utf8)
        identity.append(0)
        identity.append(contentsOf: input.normalizedAPIKey.utf8)
        return Data(SHA256.hash(data: identity))
    }

    private static func makeDefaultFetcher() -> Fetcher {
        { input in
            let provider = LLMModelProvider(
                baseURL: input.baseURL,
                apiKey: input.apiKey
            )
            return try await provider.fetchModels()
        }
    }

    private static func errorMessage(from error: Error) -> String {
        if let typolessError = error as? TypolessError {
            return typolessError.userMessage
        }
        if let configError = error as? ConfigValidationError {
            return configError.errorDescription ?? error.localizedDescription
        }
        return "无法获取模型列表，可手动输入 Model"
    }
}
