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

    func testStartRecordingFailsBeforeHUDWhenAccessibilityPermissionMissing() {
        let learner = MockPostInjectionLearner()
        let coordinator = makeCoordinator(
            dictionaryStore: PersonalDictionaryStore(directoryURL: tempDirectory),
            learner: learner,
            ensureMicrophoneAuthorized: {},
            ensureAccessibilityAuthorized: {
                throw PermissionError.accessibilityPermissionDenied
            }
        )

        var receivedEvents: [SessionFeedbackEvent] = []
        coordinator.onFeedbackEvent = { event in
            receivedEvents.append(event)
        }

        coordinator.startRecording()

        XCTAssertEqual(coordinator.state, .error)
        XCTAssertEqual(coordinator.currentError, .accessibilityPermissionDenied)
        XCTAssertEqual(receivedEvents.count, 1)
        guard case .processingFailed(.permissionDenied) = receivedEvents.first else {
            return XCTFail("expected permission failure event")
        }
    }

    func testQuickStartThenImmediateStopSilentlyCancelsWithoutProcessingHUD() throws {
        let learner = MockPostInjectionLearner()
        let coordinator = makeCoordinator(
            dictionaryStore: PersonalDictionaryStore(directoryURL: tempDirectory),
            learner: learner,
            ensureMicrophoneAuthorized: {},
            ensureAccessibilityAuthorized: {},
            configureConfigStore: { configStore in
                var config = ASRConfig()
                config.selectedPlatform = .tencentCloudSentence
                config.tencentCloud.secretId = "test-secret-id"
                config.tencentCloud.secretKey = "test-secret-key"
                try! configStore.saveASRConfig(config)
                try! configStore.updateCloudValidationState(
                    for: .tencentCloudSentence,
                    status: .verified
                )
            }
        )

        var receivedEvents: [SessionFeedbackEvent] = []
        coordinator.onFeedbackEvent = { event in
            receivedEvents.append(event)
        }

        coordinator.startRecording()
        coordinator.finishRecording()

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(coordinator.currentError)
        XCTAssertNil(coordinator.lastRecordedAudio)
        XCTAssertEqual(receivedEvents.count, 2)
        guard case .recordingStarted = receivedEvents[0] else {
            return XCTFail("expected recordingStarted event")
        }
        guard case .processingCancelled = receivedEvents[1] else {
            return XCTFail("expected processingCancelled event")
        }
    }

    private func makeCoordinator(
        dictionaryStore: PersonalDictionaryStore?,
        learner: any PostInjectionDictionaryLearning,
        ensureMicrophoneAuthorized: @escaping @MainActor @Sendable () throws -> Void = {
            try PermissionsManager().ensureMicrophoneAuthorized()
        },
        ensureAccessibilityAuthorized: @escaping @MainActor @Sendable () throws -> Void = {
            try PermissionsManager().ensureAccessibilityAuthorized()
        },
        configureConfigStore: (@MainActor (ConfigStore) -> Void)? = nil
    ) -> SessionCoordinator {
        let configStore = ConfigStore(configDirectory: tempDirectory)
        configureConfigStore?(configStore)
        let audioDeviceManager = AudioDeviceManager(configStore: configStore)
        return SessionCoordinator(
            permissionsManager: PermissionsManager(),
            configStore: configStore,
            audioDeviceManager: audioDeviceManager,
            dictionaryStore: dictionaryStore,
            postInjectionLearner: learner,
            ensureMicrophoneAuthorized: ensureMicrophoneAuthorized,
            ensureAccessibilityAuthorized: ensureAccessibilityAuthorized
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
