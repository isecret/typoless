import XCTest
@testable import Typoless

final class PostInjectionDictionaryLearnerTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    @MainActor
    func testExtractReplacementReturnsSingleContinuousReplacement() {
        let replacement = PostInjectionDictionaryLearner.extractReplacement(
            from: "请联系普林开会",
            to: "请联系朴邻开会"
        )

        XCTAssertEqual(
            replacement,
            LearnedTermReplacement(
                oldSpan: "普林",
                newSpan: "朴邻",
                surroundingTextBefore: "请联系",
                surroundingTextAfter: "开会"
            )
        )
    }

    @MainActor
    func testExtractReplacementRejectsInsertionAndDeletionOnly() {
        XCTAssertNil(
            PostInjectionDictionaryLearner.extractReplacement(
                from: "朴邻",
                to: "超级朴邻"
            )
        )
        XCTAssertNil(
            PostInjectionDictionaryLearner.extractReplacement(
                from: "客户成功部",
                to: "客户部"
            )
        )
    }

    @MainActor
    func testLearnableTermRejectsInvalidCandidates() {
        XCTAssertNil(PostInjectionDictionaryLearner.learnableTerm(from: "1"))
        XCTAssertNil(PostInjectionDictionaryLearner.learnableTerm(from: "12345"))
        XCTAssertNil(PostInjectionDictionaryLearner.learnableTerm(from: "！！！"))
        XCTAssertNil(PostInjectionDictionaryLearner.learnableTerm(from: "完整句子。"))
        XCTAssertNil(PostInjectionDictionaryLearner.learnableTerm(from: "两\n行"))
    }

    @MainActor
    func testObserveLearnsReplacementAndUpdatesBaseline() async {
        let store = PersonalDictionaryStore(directoryURL: tempDirectory)
        let evaluator = MockProperNounEvaluator { candidate in
            if candidate.replacedSpan == "朴邻" || candidate.replacedSpan == "飞书" {
                return .accept
            }
            return .reject
        }
        let sequence = SnapshotSequence([
            .init(pid: 42, bundleID: "com.example.app", value: "联系普林"),
            .init(pid: 42, bundleID: "com.example.app", value: "联系朴邻"),
            .init(pid: 42, bundleID: "com.example.app", value: "联系飞书"),
            nil
        ])
        let learner = PostInjectionDictionaryLearner(
            snapshotProvider: { _, _ in sequence.current },
            termEvaluator: evaluator,
            sleep: { _ in sequence.advance() }
        )

        var learnedTerms: [String] = []
        await learner.observe(
            targetPID: 42,
            targetBundleID: "com.example.app",
            windowContext: nil,
            store: store,
            shouldContinue: { true },
            onDecision: { decision in
                guard case .learned(let term) = decision else { return }
                learnedTerms.append(term)
            }
        )

        XCTAssertEqual(learnedTerms, ["朴邻", "飞书"])
        XCTAssertEqual(store.entries.map(\.term), ["朴邻", "飞书"])
        XCTAssertEqual(store.entries.map(\.source), [.autoLearned, .autoLearned])
    }

    @MainActor
    func testObserveRejectsCommonWordReplacement() async {
        let store = PersonalDictionaryStore(directoryURL: tempDirectory)
        let evaluator = MockProperNounEvaluator { candidate in
            XCTAssertEqual(candidate.originalSpan, "然后")
            XCTAssertEqual(candidate.replacedSpan, "关闭")
            XCTAssertEqual(candidate.surroundingTextBefore, "请")
            XCTAssertEqual(candidate.surroundingTextAfter, "窗口")
            return .reject
        }
        let sequence = SnapshotSequence([
            .init(pid: 42, bundleID: "com.example.app", value: "请然后窗口"),
            .init(pid: 42, bundleID: "com.example.app", value: "请关闭窗口"),
            nil
        ])
        let learner = PostInjectionDictionaryLearner(
            snapshotProvider: { _, _ in sequence.current },
            termEvaluator: evaluator,
            sleep: { _ in sequence.advance() }
        )

        var decisions: [PostInjectionLearningDecision] = []
        await learner.observe(
            targetPID: 42,
            targetBundleID: "com.example.app",
            windowContext: nil,
            store: store,
            shouldContinue: { true },
            onDecision: { decisions.append($0) }
        )

        XCTAssertEqual(decisions, [.rejected("关闭")])
        XCTAssertTrue(store.entries.isEmpty)
    }

    @MainActor
    func testObserveReportsEvaluationFailureWithoutLearning() async {
        let store = PersonalDictionaryStore(directoryURL: tempDirectory)
        let evaluator = MockProperNounEvaluator { _ in
            throw ProperNounLearningEvaluationError.invalidResponse
        }
        let sequence = SnapshotSequence([
            .init(pid: 42, bundleID: "com.example.app", value: "联系普林"),
            .init(pid: 42, bundleID: "com.example.app", value: "联系朴邻"),
            nil
        ])
        let learner = PostInjectionDictionaryLearner(
            snapshotProvider: { _, _ in sequence.current },
            termEvaluator: evaluator,
            sleep: { _ in sequence.advance() }
        )

        var decisions: [PostInjectionLearningDecision] = []
        await learner.observe(
            targetPID: 42,
            targetBundleID: "com.example.app",
            windowContext: nil,
            store: store,
            shouldContinue: { true },
            onDecision: { decisions.append($0) }
        )

        XCTAssertEqual(decisions, [.failed("朴邻", reason: "invalid_response")])
        XCTAssertTrue(store.entries.isEmpty)
    }

    private final class SnapshotSequence: @unchecked Sendable {
        private let snapshots: [FocusedElementTextSnapshot?]
        private(set) var index = 0

        init(_ snapshots: [FocusedElementTextSnapshot?]) {
            self.snapshots = snapshots
        }

        var current: FocusedElementTextSnapshot? {
            guard index < snapshots.count else { return nil }
            return snapshots[index]
        }

        func advance() {
            index += 1
        }
    }

    private struct MockProperNounEvaluator: ProperNounLearningEvaluating {
        let handler: @MainActor @Sendable (ProperNounLearningCandidate) async throws -> ProperNounLearningDecision

        init(
            handler: @escaping @MainActor @Sendable (ProperNounLearningCandidate) async throws -> ProperNounLearningDecision
        ) {
            self.handler = handler
        }

        func evaluate(_ candidate: ProperNounLearningCandidate) async throws -> ProperNounLearningDecision {
            try await handler(candidate)
        }
    }
}
