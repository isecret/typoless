import Foundation

@MainActor
@Observable
final class LLMModelListService {
    typealias Fetcher = @Sendable (LLMModelListInput) async throws -> [String]

    private let fetcher: Fetcher
    private var loadTask: Task<Void, Never>?
    private var activeFingerprint: String?
    private var lastCompletedFingerprint: String?

    private(set) var status: LLMModelListStatus = .incomplete
    private(set) var models: [String] = []
    private(set) var lastErrorMessage: String?

    init(fetcher: Fetcher? = nil) {
        self.fetcher = fetcher ?? Self.makeDefaultFetcher()
    }

    func load(_ input: LLMModelListInput, force: Bool = false) {
        let normalizedInput = input.normalized()

        guard normalizedInput.isComplete else {
            cancelOngoingLoad()
            activeFingerprint = nil
            lastCompletedFingerprint = nil
            status = .incomplete
            models = []
            lastErrorMessage = nil
            return
        }

        let fingerprint = normalizedInput.fingerprint
        if !force {
            if activeFingerprint == fingerprint {
                return
            }
            if lastCompletedFingerprint == fingerprint, status != .loading {
                return
            }
        }

        loadTask?.cancel()
        activeFingerprint = fingerprint
        status = .loading
        lastErrorMessage = nil

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
                guard let self, self.activeFingerprint == fingerprint else { return }
                self.activeFingerprint = nil
                self.lastCompletedFingerprint = fingerprint
                self.loadTask = nil

                switch result {
                case .success(let models):
                    self.models = models
                    self.status = .loaded
                    self.lastErrorMessage = nil
                case .failure(let error):
                    self.models = []
                    self.status = .unavailable
                    self.lastErrorMessage = Self.errorMessage(from: error)
                }
            }
        }
    }

    private func cancelOngoingLoad() {
        loadTask?.cancel()
        loadTask = nil
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
        return error.localizedDescription
    }
}
