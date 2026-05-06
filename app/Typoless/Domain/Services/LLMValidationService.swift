import Foundation

@MainActor
@Observable
final class LLMValidationService {
    typealias Validator = @Sendable (LLMValidationInput, @escaping @MainActor @Sendable () -> Void) async throws -> Void

    private let validator: Validator
    private let onThinkingUnsupported: @MainActor @Sendable () -> Void

    private var validationTask: Task<Void, Never>?
    private var activeFingerprint: String?
    private var lastCompletedFingerprint: String?

    private(set) var status: LLMModelStatus = .incomplete
    private(set) var lastErrorMessage: String?

    init(
        onThinkingUnsupported: @escaping @MainActor @Sendable () -> Void = {},
        validator: @escaping Validator = LLMValidationService.defaultValidator
    ) {
        self.onThinkingUnsupported = onThinkingUnsupported
        self.validator = validator
    }

    func validate(_ input: LLMValidationInput, force: Bool = false) {
        let normalizedInput = input.normalized()

        guard normalizedInput.isComplete else {
            cancelOngoingValidation()
            activeFingerprint = nil
            lastCompletedFingerprint = nil
            status = .incomplete
            lastErrorMessage = nil
            return
        }

        let fingerprint = normalizedInput.fingerprint
        if !force {
            if activeFingerprint == fingerprint {
                return
            }
            if lastCompletedFingerprint == fingerprint, status != .checking {
                return
            }
        }

        validationTask?.cancel()
        activeFingerprint = fingerprint
        status = .checking
        lastErrorMessage = nil

        let validator = self.validator
        let onThinkingUnsupported = self.onThinkingUnsupported

        validationTask = Task { [weak self] in
            let result: Result<Void, Error>
            do {
                try await validator(normalizedInput, onThinkingUnsupported)
                result = .success(())
            } catch {
                result = .failure(error)
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, self.activeFingerprint == fingerprint else { return }
                self.activeFingerprint = nil
                self.lastCompletedFingerprint = fingerprint
                self.validationTask = nil

                switch result {
                case .success:
                    self.status = .ready
                    self.lastErrorMessage = nil
                case .failure(let error):
                    self.status = .failed
                    self.lastErrorMessage = Self.errorMessage(from: error)
                }
            }
        }
    }

    private func cancelOngoingValidation() {
        validationTask?.cancel()
        validationTask = nil
    }

    private static func defaultValidator(
        input: LLMValidationInput,
        onThinkingUnsupported: @escaping @MainActor @Sendable () -> Void
    ) async throws {
        let provider = LLMProvider(
            baseURL: input.baseURL,
            apiKey: input.apiKey,
            model: input.model,
            thinkingDisabled: input.thinkingDisabled,
            onThinkingUnsupported: onThinkingUnsupported
        )
        try await provider.validateConfiguration()
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
