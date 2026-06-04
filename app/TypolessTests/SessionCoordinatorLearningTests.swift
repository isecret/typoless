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

    func testStartRecordingFailsBeforeHUDWhenAccessibilityPermissionMissing() async {
        let learner = MockPostInjectionLearner()
        let coordinator = makeCoordinator(
            dictionaryStore: PersonalDictionaryStore(directoryURL: tempDirectory),
            learner: learner,
            prepareForVoiceInputStart: {
                throw PermissionError.accessibilityPermissionDenied
            }
        )

        var receivedEvents: [SessionFeedbackEvent] = []
        coordinator.onFeedbackEvent = { event in
            receivedEvents.append(event)
        }

        coordinator.startRecording()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(coordinator.state, .error)
        XCTAssertEqual(coordinator.currentError, .accessibilityPermissionDenied)
        XCTAssertEqual(receivedEvents.count, 1)
        guard case .processingFailed(.permissionDenied) = receivedEvents.first else {
            return XCTFail("expected permission failure event")
        }
    }

    func testStartRecordingFailsBeforeHUDWhenMicrophonePermissionMissing() async {
        let learner = MockPostInjectionLearner()
        let coordinator = makeCoordinator(
            dictionaryStore: PersonalDictionaryStore(directoryURL: tempDirectory),
            learner: learner,
            prepareForVoiceInputStart: {
                throw PermissionError.microphonePermissionDenied
            }
        )

        var receivedEvents: [SessionFeedbackEvent] = []
        coordinator.onFeedbackEvent = { event in
            receivedEvents.append(event)
        }

        coordinator.startRecording()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(coordinator.state, .error)
        XCTAssertEqual(coordinator.currentError, .microphonePermissionDenied)
        XCTAssertEqual(receivedEvents.count, 1)
        guard case .processingFailed(.permissionDenied) = receivedEvents.first else {
            return XCTFail("expected permission failure event")
        }
    }

    func testStartRecordingRunsPermissionPreparationBeforeResourceValidation() async {
        let learner = MockPostInjectionLearner()
        let tracker = PermissionPreparationTracker()
        let coordinator = makeCoordinator(
            dictionaryStore: PersonalDictionaryStore(directoryURL: tempDirectory),
            learner: learner,
            prepareForVoiceInputStart: {
                await tracker.prepare()
            }
        )

        coordinator.startRecording()
        try? await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(await tracker.callCount, 1)
        XCTAssertNotEqual(coordinator.state, .preparing)
        XCTAssertNotEqual(coordinator.currentError, .microphonePermissionDenied)
        XCTAssertNotEqual(coordinator.currentError, .accessibilityPermissionDenied)
    }

    func testStartRecordingEntersRecordingWhenPermissionsAndResourcesAreReady() async throws {
        let learner = MockPostInjectionLearner()
        let tracker = PermissionPreparationTracker()
        var asrConfig = ASRConfig()
        asrConfig.selectedPlatform = .tencentCloudSentence
        asrConfig.tencentCloud.secretId = "id"
        asrConfig.tencentCloud.secretKey = "key"
        asrConfig.tencentCloud.validationStatus = .verified
        let coordinator = makeCoordinator(
            dictionaryStore: PersonalDictionaryStore(directoryURL: tempDirectory),
            learner: learner,
            asrConfig: asrConfig,
            prepareForVoiceInputStart: {
                await tracker.prepare()
            },
            validateDenoiseResources: {},
            validateASRResources: {},
            recordingStartDelay: .seconds(5)
        )

        var receivedEvents: [SessionFeedbackEvent] = []
        coordinator.onFeedbackEvent = { event in
            receivedEvents.append(event)
        }

        coordinator.startRecording()
        await waitUntil {
            coordinator.state == .recording
        }

        XCTAssertEqual(await tracker.callCount, 1)
        XCTAssertEqual(coordinator.state, .recording)
        XCTAssertNil(coordinator.currentError)
        XCTAssertEqual(receivedEvents.count, 1)
        guard case .recordingStarted = receivedEvents.first else {
            return XCTFail("expected recordingStarted event")
        }

        coordinator.cancel()
    }

    func testQuickStartThenImmediateStopSilentlyCancelsWithoutProcessingHUD() async throws {
        let learner = MockPostInjectionLearner()
        let tracker = PermissionPreparationTracker()
        var asrConfig = ASRConfig()
        asrConfig.selectedPlatform = .tencentCloudSentence
        asrConfig.tencentCloud.secretId = "test-secret-id"
        asrConfig.tencentCloud.secretKey = "test-secret-key"
        asrConfig.tencentCloud.validationStatus = .verified
        let coordinator = makeCoordinator(
            dictionaryStore: PersonalDictionaryStore(directoryURL: tempDirectory),
            learner: learner,
            asrConfig: asrConfig,
            prepareForVoiceInputStart: {
                await tracker.prepare()
            },
            validateDenoiseResources: {},
            validateASRResources: {},
            recordingStartDelay: .seconds(5)
        )

        var receivedEvents: [SessionFeedbackEvent] = []
        coordinator.onFeedbackEvent = { event in
            receivedEvents.append(event)
        }

        coordinator.startRecording()
        await waitUntil {
            coordinator.state == .recording
        }
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

    func testStartRecordingDoesNotLaunchMultiplePermissionPreparations() async {
        let learner = MockPostInjectionLearner()
        let gate = PermissionPreparationGate()
        let coordinator = makeCoordinator(
            dictionaryStore: PersonalDictionaryStore(directoryURL: tempDirectory),
            learner: learner,
            prepareForVoiceInputStart: {
                await gate.prepare()
            }
        )

        coordinator.startRecording()
        coordinator.startRecording()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(coordinator.state, .preparing)
        XCTAssertEqual(await gate.callCount, 1)

        await gate.release()
        try? await Task.sleep(for: .milliseconds(50))
    }

    private func makeCoordinator(
        dictionaryStore: PersonalDictionaryStore?,
        learner: any PostInjectionDictionaryLearning,
        asrConfig: ASRConfig? = nil,
        prepareForVoiceInputStart: @escaping @MainActor @Sendable () async throws -> Void = {
            try await PermissionsManager().prepareForVoiceInputStart()
        },
        ensureMicrophoneAuthorized: (@MainActor @Sendable () throws -> Void)? = nil,
        ensureAccessibilityAuthorized: (@MainActor @Sendable () throws -> Void)? = nil,
        configureConfigStore: (@MainActor (ConfigStore) -> Void)? = nil,
        validateDenoiseResources: @escaping @MainActor @Sendable () throws -> Void = {
            try ResourceValidator.validateDenoiseResources()
        },
        validateASRResources: @escaping @MainActor @Sendable () throws -> Void = {
            try ResourceValidator.validateASRResources()
        },
        recordingStartDelay: Duration = .milliseconds(16)
    ) -> SessionCoordinator {
        let configStore = ConfigStore(configDirectory: tempDirectory)
        configureConfigStore?(configStore)
        if let asrConfig {
            try? configStore.saveASRConfig(asrConfig)
        }
        let audioDeviceManager = AudioDeviceManager(configStore: configStore)
        return SessionCoordinator(
            permissionsManager: PermissionsManager(),
            configStore: configStore,
            audioDeviceManager: audioDeviceManager,
            dictionaryStore: dictionaryStore,
            postInjectionLearner: learner,
            prepareForVoiceInputStart: prepareForVoiceInputStart,
            ensureMicrophoneAuthorized: ensureMicrophoneAuthorized,
            ensureAccessibilityAuthorized: ensureAccessibilityAuthorized,
            validateDenoiseResources: validateDenoiseResources,
            validateASRResources: validateASRResources,
            recordingStartDelay: recordingStartDelay
        )
    }

    private func waitUntil(
        timeout: Duration = .milliseconds(250),
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private actor PermissionPreparationTracker {
        private(set) var callCount = 0

        func prepare() {
            callCount += 1
        }
    }

    private actor PermissionPreparationGate {
        private(set) var callCount = 0
        private var continuation: CheckedContinuation<Void, Never>?

        func prepare() async {
            callCount += 1
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }

        func release() {
            continuation?.resume()
            continuation = nil
        }
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
