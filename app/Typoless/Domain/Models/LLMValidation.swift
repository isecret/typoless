import Foundation

enum LLMModelStatus: Equatable, Sendable {
    case incomplete
    case checking
    case ready
    case failed
}

struct LLMValidationInput: Equatable, Sendable {
    var baseURL: String
    var apiKey: String
    var model: String
    var thinkingDisabled: Bool

    var normalizedBaseURL: String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isComplete: Bool {
        !normalizedBaseURL.isEmpty
            && !normalizedAPIKey.isEmpty
            && !normalizedModel.isEmpty
    }

    var fingerprint: String {
        "\(normalizedBaseURL)\n\(normalizedAPIKey)\n\(normalizedModel)\n\(thinkingDisabled)"
    }

    func normalized() -> Self {
        Self(
            baseURL: normalizedBaseURL,
            apiKey: normalizedAPIKey,
            model: normalizedModel,
            thinkingDisabled: thinkingDisabled
        )
    }
}
