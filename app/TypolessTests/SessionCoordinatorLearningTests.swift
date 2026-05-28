import XCTest
@testable import Typoless

@MainActor
final class SessionCoordinatorLearningTests: XCTestCase {
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

    func testBeginPostInjectionLearningSkipsTranslateMode() async {
        let learner = MockPostInjectionLearner()
        let coordinator = makeCoordinator(
            dictionaryStore: PersonalDictionaryStore(directoryURL: tempDirectory),
            learner: learner
        )

        coordinator.beginPostInjectionLearningIfNeeded(
            generation: 0,
            mode: .translate,
            sessionID: "session-test",
            targetPID: 42,
            targetBundleID: "com.example.app"
        )

        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(learner.observeCallCount, 0)
    }

    func testBeginPostInjectionLearningEmitsHUDNoticeForLearnedTerm() async {
        let learner = MockPostInjectionLearner()
        learner.learnedTerm = "朴邻"
        let coordinator = makeCoordinator(
            dictionaryStore: PersonalDictionaryStore(directoryURL: tempDirectory),
            learner: learner
        )

        var receivedEvents: [SessionFeedbackEvent] = []
        coordinator.onFeedbackEvent = { event in
            receivedEvents.append(event)
        }

        coordinator.beginPostInjectionLearningIfNeeded(
            generation: 0,
            mode: .polish,
            sessionID: "session-test",
            targetPID: 42,
            targetBundleID: "com.example.app"
        )

        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(learner.observeCallCount, 1)
        XCTAssertEqual(receivedEvents.count, 1)
        guard case .dictionaryTermLearned(let term) = receivedEvents.first else {
            return XCTFail("expected dictionaryTermLearned event")
        }
        XCTAssertEqual(term, "朴邻")
    }

    private func makeCoordinator(
        dictionaryStore: PersonalDictionaryStore?,
        learner: any PostInjectionDictionaryLearning
    ) -> SessionCoordinator {
        let configStore = ConfigStore(configDirectory: tempDirectory)
        let audioDeviceManager = AudioDeviceManager(configStore: configStore)
        return SessionCoordinator(
            permissionsManager: PermissionsManager(),
            configStore: configStore,
            audioDeviceManager: audioDeviceManager,
            dictionaryStore: dictionaryStore,
            postInjectionLearner: learner
        )
    }

    private final class MockPostInjectionLearner: PostInjectionDictionaryLearning, @unchecked Sendable {
        var observeCallCount = 0
        var learnedTerm: String?

        func observe(
            targetPID: pid_t?,
            targetBundleID: String?,
            windowContext: WindowContextSnapshot?,
            store: PersonalDictionaryStore,
            shouldContinue: @escaping @MainActor @Sendable () -> Bool,
            onDecision: @escaping @MainActor @Sendable (PostInjectionLearningDecision) -> Void
        ) async {
            observeCallCount += 1
            guard shouldContinue(), let learnedTerm else { return }
            _ = try? store.addLearnedTermIfNeeded(learnedTerm)
            onDecision(.learned(learnedTerm))
        }
    }
}
