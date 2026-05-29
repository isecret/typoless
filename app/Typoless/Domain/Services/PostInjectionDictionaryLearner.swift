import Foundation
import os

@MainActor
protocol PostInjectionDictionaryLearning: Sendable {
    func observe(
        targetPID: pid_t?,
        targetBundleID: String?,
        windowContext: WindowContextSnapshot?,
        store: PersonalDictionaryStore,
        shouldContinue: @escaping @MainActor @Sendable () -> Bool,
        onDecision: @escaping @MainActor @Sendable (PostInjectionLearningDecision) -> Void
    ) async
}

struct LearnedTermReplacement: Equatable, Sendable {
    let oldSpan: String
    let newSpan: String
    let surroundingTextBefore: String
    let surroundingTextAfter: String
}

struct ProperNounLearningCandidate: Equatable, Sendable {
    let originalSpan: String
    let replacedSpan: String
    let selectedText: String?
    let surroundingTextBefore: String?
    let surroundingTextAfter: String?
}

enum ProperNounLearningDecision: String, Decodable, Sendable {
    case accept
    case reject
}

enum PostInjectionLearningDecision: Equatable, Sendable {
    case learned(String)
    case rejected(String)
    case failed(String, reason: String)
}

enum ProperNounLearningEvaluationError: Error {
    case unavailableProvider
    case invalidResponse
}

@MainActor
protocol ProperNounLearningEvaluating: Sendable {
    func evaluate(_ candidate: ProperNounLearningCandidate) async throws -> ProperNounLearningDecision
}

struct LLMProperNounTermEvaluator: ProperNounLearningEvaluating, Sendable {
    typealias ProviderFactory = @MainActor @Sendable () -> LLMProvider?

    private let providerFactory: ProviderFactory

    init(providerFactory: @escaping ProviderFactory) {
        self.providerFactory = providerFactory
    }

    func evaluate(_ candidate: ProperNounLearningCandidate) async throws -> ProperNounLearningDecision {
        guard let provider = providerFactory() else {
            throw ProperNounLearningEvaluationError.unavailableProvider
        }
        return try await provider.classifyProperNounLearningCandidate(candidate)
    }
}

@MainActor
struct PostInjectionDictionaryLearner: PostInjectionDictionaryLearning, Sendable {
    static let observationDuration: Duration = .seconds(30)
    static let pollInterval: Duration = .milliseconds(500)
    static let maxLearnedTermLength = 24
    private static let maxContextGlyphCount = 80
    private static let logger = Logger(
        subsystem: "com.isecret.typoless",
        category: "DictionaryLearning"
    )

    typealias SnapshotProvider = @MainActor @Sendable (pid_t?, String?) -> FocusedElementTextSnapshot?
    typealias Sleep = @Sendable (Duration) async -> Void

    private let snapshotProvider: SnapshotProvider
    private let sleep: Sleep
    private let termEvaluator: any ProperNounLearningEvaluating

    init(
        snapshotProvider: @escaping SnapshotProvider = { targetPID, targetBundleID in
            FocusedElementTextSnapshotReader().read(
                targetPID: targetPID,
                targetBundleID: targetBundleID
            )
        },
        termEvaluator: any ProperNounLearningEvaluating,
        sleep: @escaping Sleep = { duration in
            try? await Task.sleep(for: duration)
        }
    ) {
        self.snapshotProvider = snapshotProvider
        self.termEvaluator = termEvaluator
        self.sleep = sleep
    }

    func observe(
        targetPID: pid_t?,
        targetBundleID: String?,
        windowContext: WindowContextSnapshot?,
        store: PersonalDictionaryStore,
        shouldContinue: @escaping @MainActor @Sendable () -> Bool,
        onDecision: @escaping @MainActor @Sendable (PostInjectionLearningDecision) -> Void
    ) async {
        guard shouldContinue() else { return }
        guard let baseline = snapshotProvider(targetPID, targetBundleID)?.value else { return }

        let deadline = ContinuousClock.now + Self.observationDuration
        var currentBaseline = baseline

        while shouldContinue(), !Task.isCancelled, ContinuousClock.now < deadline {
            await sleep(Self.pollInterval)
            guard shouldContinue(), !Task.isCancelled else { return }
            guard let snapshot = snapshotProvider(targetPID, targetBundleID) else { return }

            let latestValue = snapshot.value
            guard latestValue != currentBaseline else { continue }

            if let replacement = Self.extractReplacement(from: currentBaseline, to: latestValue),
               let learnedTerm = Self.learnableTerm(from: replacement.newSpan) {
                let candidate = ProperNounLearningCandidate(
                    originalSpan: replacement.oldSpan,
                    replacedSpan: learnedTerm,
                    selectedText: Self.normalizedOptional(windowContext?.selectedText),
                    surroundingTextBefore: Self.trimTrailingContext(replacement.surroundingTextBefore),
                    surroundingTextAfter: Self.trimLeadingContext(replacement.surroundingTextAfter)
                )
                Self.logCandidate(candidate, replacement: replacement)

                do {
                    let decision = try await termEvaluator.evaluate(candidate)
                    Self.logDecision(decision, term: learnedTerm)
                    switch decision {
                    case .accept:
                        if (try? store.addLearnedTermIfNeeded(learnedTerm)) == true {
                            onDecision(.learned(learnedTerm))
                        }
                    case .reject:
                        onDecision(.rejected(learnedTerm))
                    }
                } catch {
                    Self.logFailure(error, term: learnedTerm, candidate: candidate)
                    onDecision(.failed(learnedTerm, reason: Self.failureReason(from: error)))
                }
            } else if let replacement = Self.extractReplacement(from: currentBaseline, to: latestValue) {
                Self.logFilteredReplacement(replacement)
            }

            currentBaseline = latestValue
        }
    }

    static func extractReplacement(from original: String, to updated: String) -> LearnedTermReplacement? {
        guard original != updated else { return nil }

        let originalGlyphs = Array(original)
        let updatedGlyphs = Array(updated)
        let sharedPrefix = commonPrefixLength(originalGlyphs, updatedGlyphs)
        let sharedSuffix = commonSuffixLength(
            originalGlyphs,
            updatedGlyphs,
            prefixLength: sharedPrefix
        )

        let originalEnd = originalGlyphs.count - sharedSuffix
        let updatedEnd = updatedGlyphs.count - sharedSuffix

        guard sharedPrefix < originalEnd, sharedPrefix < updatedEnd else {
            return nil
        }

        let oldSpan = String(originalGlyphs[sharedPrefix..<originalEnd])
        let newSpan = String(updatedGlyphs[sharedPrefix..<updatedEnd])
        guard !oldSpan.isEmpty, !newSpan.isEmpty else { return nil }

        let before = String(updatedGlyphs[..<sharedPrefix])
        let after = String(updatedGlyphs[updatedEnd...])

        return LearnedTermReplacement(
            oldSpan: oldSpan,
            newSpan: newSpan,
            surroundingTextBefore: before,
            surroundingTextAfter: after
        )
    }

    static func learnableTerm(from replacement: String) -> String? {
        let normalized = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let glyphs = Array(normalized)
        guard glyphs.count >= 2, glyphs.count <= maxLearnedTermLength else {
            return nil
        }

        guard !normalized.contains(where: \.isNewline) else { return nil }
        guard !normalized.allSatisfy({ $0.isNumber }) else { return nil }
        guard !normalized.allSatisfy(Self.isPunctuationLike) else { return nil }
        guard normalized.allSatisfy(Self.isChineseCharacter) else { return nil }

        let sentenceEndingCharacters = CharacterSet(charactersIn: "。！？!?；;")
        if let scalar = normalized.unicodeScalars.last,
           sentenceEndingCharacters.contains(scalar) {
            return nil
        }

        return normalized
    }

    private static func commonPrefixLength(_ lhs: [Character], _ rhs: [Character]) -> Int {
        var index = 0
        while index < lhs.count, index < rhs.count, lhs[index] == rhs[index] {
            index += 1
        }
        return index
    }

    private static func commonSuffixLength(
        _ lhs: [Character],
        _ rhs: [Character],
        prefixLength: Int
    ) -> Int {
        var suffixLength = 0

        while suffixLength < lhs.count - prefixLength,
              suffixLength < rhs.count - prefixLength,
              lhs[lhs.count - 1 - suffixLength] == rhs[rhs.count - 1 - suffixLength] {
            suffixLength += 1
        }

        return suffixLength
    }

    private static func isPunctuationLike(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.symbols.contains(scalar)
                || CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
    }

    private static func isChineseCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF,   // CJK Unified Ideographs Extension A
                 0x4E00...0x9FFF,   // CJK Unified Ideographs
                 0xF900...0xFAFF,   // CJK Compatibility Ideographs
                 0x20000...0x2A6DF, // CJK Unified Ideographs Extension B
                 0x2A700...0x2B73F, // CJK Unified Ideographs Extension C
                 0x2B740...0x2B81F, // CJK Unified Ideographs Extension D
                 0x2B820...0x2CEAF, // CJK Unified Ideographs Extension E/F
                 0x2CEB0...0x2EBEF, // CJK Unified Ideographs Extension F/I
                 0x30000...0x3134F: // CJK Unified Ideographs Extension G/H
                return true
            default:
                return false
            }
        }
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func trimTrailingContext(_ text: String) -> String? {
        let normalized = normalizedOptional(text)
        guard let normalized else { return nil }
        let glyphs = Array(normalized)
        if glyphs.count <= maxContextGlyphCount {
            return normalized
        }
        return String(glyphs.suffix(maxContextGlyphCount))
    }

    private static func trimLeadingContext(_ text: String) -> String? {
        let normalized = normalizedOptional(text)
        guard let normalized else { return nil }
        let glyphs = Array(normalized)
        if glyphs.count <= maxContextGlyphCount {
            return normalized
        }
        return String(glyphs.prefix(maxContextGlyphCount))
    }

    private static func failureReason(from error: Error) -> String {
        switch error {
        case ProperNounLearningEvaluationError.unavailableProvider:
            return "llm_unavailable"
        case ProperNounLearningEvaluationError.invalidResponse:
            return "invalid_response"
        case let error as TypolessError:
            return error.diagnosticClassification
        default:
            return String(describing: error)
        }
    }

    private static func logCandidate(
        _ candidate: ProperNounLearningCandidate,
        replacement: LearnedTermReplacement
    ) {
        #if DEBUG
        logger.debug(
            """
            candidate \
            | old="\(replacement.oldSpan, privacy: .public)" \
            | new="\(replacement.newSpan, privacy: .public)" \
            | before="\(candidate.surroundingTextBefore ?? "", privacy: .public)" \
            | after="\(candidate.surroundingTextAfter ?? "", privacy: .public)" \
            | selected="\(candidate.selectedText ?? "", privacy: .public)"
            """
        )
        #else
        _ = candidate
        _ = replacement
        #endif
    }

    private static func logDecision(_ decision: ProperNounLearningDecision, term: String) {
        #if DEBUG
        logger.debug(
            "decision | term=\"\(term, privacy: .public)\" | result=\(decision.rawValue, privacy: .public)"
        )
        #else
        _ = decision
        _ = term
        #endif
    }

    private static func logFailure(
        _ error: Error,
        term: String,
        candidate: ProperNounLearningCandidate
    ) {
        let reason = failureReason(from: error)
        #if DEBUG
        logger.error(
            """
            failure \
            | term="\(term, privacy: .public)" \
            | reason=\(reason, privacy: .public) \
            | original="\(candidate.originalSpan, privacy: .public)" \
            | replaced="\(candidate.replacedSpan, privacy: .public)"
            """
        )
        #else
        _ = candidate
        logger.error("failure | chars=\(term.count) | reason=\(reason, privacy: .public)")
        #endif
    }

    private static func logFilteredReplacement(_ replacement: LearnedTermReplacement) {
        #if DEBUG
        logger.debug(
            """
            filtered \
            | old="\(replacement.oldSpan, privacy: .public)" \
            | new="\(replacement.newSpan, privacy: .public)"
            """
        )
        #else
        _ = replacement
        #endif
    }
}
