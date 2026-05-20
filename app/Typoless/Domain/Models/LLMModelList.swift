import Foundation

enum LLMModelListStatus: Equatable, Sendable {
    case incomplete
    case loading
    case loaded
    case unavailable
}

struct LLMModelListInput: Equatable, Sendable {
    var baseURL: String
    var apiKey: String

    var normalizedBaseURL: String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isComplete: Bool {
        !normalizedBaseURL.isEmpty
            && !normalizedAPIKey.isEmpty
    }

    var fingerprint: String {
        "\(normalizedBaseURL)\n\(normalizedAPIKey)"
    }

    func normalized() -> Self {
        Self(
            baseURL: normalizedBaseURL,
            apiKey: normalizedAPIKey
        )
    }
}
