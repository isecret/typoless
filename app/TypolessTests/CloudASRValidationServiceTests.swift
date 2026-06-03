import XCTest
@testable import Typoless

final class CloudASRValidationServiceTests: XCTestCase {
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
    func testIncompleteInputDoesNotRunValidator() async {
        let store = ConfigStore(configDirectory: tempDirectory)
        let counter = ValidationCounter()
        let service = CloudASRValidationService(
            configStore: store,
            validatorFactory: { _ in
                counter.increment()
                return StubCloudASRValidator {}
            }
        )

        service.validate(
            CloudASRValidationInput(
                platform: .tencentCloudSentence,
                asrConfig: ASRConfig()
            )
        )

        XCTAssertEqual(service.status, .incomplete)
        XCTAssertNil(service.lastErrorMessage)
        XCTAssertEqual(counter.currentValue(), 0)
    }

    @MainActor
    func testSuccessfulValidationTransitionsToReadyAndPersistsState() async throws {
        let store = ConfigStore(configDirectory: tempDirectory)
        var config = store.asrConfig
        config.selectedPlatform = .tencentCloudSentence
        config.tencentCloud.secretId = "id"
        config.tencentCloud.secretKey = "key"
        try store.saveASRConfig(config)

        let service = CloudASRValidationService(
            configStore: store,
            validatorFactory: { _ in
                StubCloudASRValidator {
                    try await Task.sleep(for: .milliseconds(20))
                }
            }
        )

        service.validate(CloudASRValidationInput(platform: .tencentCloudSentence, asrConfig: store.asrConfig))

        XCTAssertEqual(service.status, .checking)
        await waitUntil { service.status == .ready }
        XCTAssertEqual(store.asrConfig.tencentCloud.validationStatus, .verified)
    }

    @MainActor
    func testValidationFailureExposesUserFacingErrorAndPersistsFailure() async throws {
        let store = ConfigStore(configDirectory: tempDirectory)
        var config = store.asrConfig
        config.selectedPlatform = .aliyunSentence
        config.aliyun.accessKeyId = "ak"
        config.aliyun.accessKeySecret = "secret"
        config.aliyun.appKey = "app"
        try store.saveASRConfig(config)

        let service = CloudASRValidationService(
            configStore: store,
            validatorFactory: { _ in
                StubCloudASRValidator {
                    throw TypolessError.cloudASRAuthenticationFailure
                }
            }
        )

        service.validate(CloudASRValidationInput(platform: .aliyunSentence, asrConfig: store.asrConfig))

        await waitUntil { service.status == .failed }
        XCTAssertEqual(service.lastErrorMessage, "云端 ASR 认证失败，请检查当前平台凭据")
        XCTAssertEqual(store.asrConfig.aliyun.validationStatus, .failed)
        XCTAssertEqual(store.asrConfig.aliyun.lastValidationError, "云端 ASR 认证失败，请检查当前平台凭据")
    }

    @MainActor
    func testLatestValidationWinsOverCancelledRequest() async throws {
        let store = ConfigStore(configDirectory: tempDirectory)
        var config = store.asrConfig
        config.selectedPlatform = .xunfeiSentence
        config.xunfei.appID = "appid"
        config.xunfei.apiKey = "key"
        config.xunfei.apiSecret = "secret"
        try store.saveASRConfig(config)

        let service = CloudASRValidationService(
            configStore: store,
            validatorFactory: { input in
                StubCloudASRValidator {
                    if input.asrConfig.xunfei.apiKey == "key" {
                        try await Task.sleep(for: .milliseconds(150))
                        throw TypolessError.cloudASRNetworkFailure(message: "old request should be cancelled")
                    }
                }
            }
        )

        service.validate(CloudASRValidationInput(platform: .xunfeiSentence, asrConfig: store.asrConfig))

        var nextConfig = store.asrConfig
        nextConfig.xunfei.apiKey = "new-key"
        try store.saveASRConfig(nextConfig)
        service.validate(CloudASRValidationInput(platform: .xunfeiSentence, asrConfig: store.asrConfig))

        await waitUntil { service.status == .ready }
        XCTAssertNil(service.lastErrorMessage)
        XCTAssertEqual(store.asrConfig.xunfei.validationStatus, .verified)
    }

    @MainActor
    func testSyncFromConfigRestoresVerifiedState() throws {
        let store = ConfigStore(configDirectory: tempDirectory)
        var config = store.asrConfig
        config.selectedPlatform = .tencentCloudSentence
        config.tencentCloud.secretId = "id"
        config.tencentCloud.secretKey = "key"
        try store.saveASRConfig(config)
        try store.updateCloudValidationState(for: .tencentCloudSentence, status: .verified)

        let service = CloudASRValidationService(configStore: store)
        service.syncFromConfig(
            for: CloudASRValidationInput(platform: .tencentCloudSentence, asrConfig: store.asrConfig)
        )

        XCTAssertEqual(service.status, .ready)
        XCTAssertNil(service.lastErrorMessage)
    }

    @MainActor
    func testSyncFromConfigRestoresFailedStateAndMessage() throws {
        let store = ConfigStore(configDirectory: tempDirectory)
        var config = store.asrConfig
        config.selectedPlatform = .aliyunSentence
        config.aliyun.accessKeyId = "ak"
        config.aliyun.accessKeySecret = "secret"
        config.aliyun.appKey = "app"
        try store.saveASRConfig(config)
        try store.updateCloudValidationState(
            for: .aliyunSentence,
            status: .failed,
            error: "云端 ASR 认证失败，请检查当前平台凭据"
        )

        let service = CloudASRValidationService(configStore: store)
        service.syncFromConfig(
            for: CloudASRValidationInput(platform: .aliyunSentence, asrConfig: store.asrConfig)
        )

        XCTAssertEqual(service.status, .failed)
        XCTAssertEqual(service.lastErrorMessage, "云端 ASR 认证失败，请检查当前平台凭据")
    }

    @MainActor
    func testSyncFromConfigTreatsPersistedValidatingAsReadyDisplayState() throws {
        let store = ConfigStore(configDirectory: tempDirectory)
        var config = store.asrConfig
        config.selectedPlatform = .volcengineSentence
        config.volcengine.apiKey = "api-key"
        try store.saveASRConfig(config)
        try store.updateCloudValidationState(for: .volcengineSentence, status: .validating)

        let service = CloudASRValidationService(configStore: store)
        service.syncFromConfig(
            for: CloudASRValidationInput(platform: .volcengineSentence, asrConfig: store.asrConfig)
        )

        XCTAssertEqual(service.status, .ready)
        XCTAssertNil(service.lastErrorMessage)
    }

    func testXiaomiMiMoValidationInputFingerprintIncludesLanguage() {
        var config = ASRConfig()
        config.xiaomiMiMo.apiKey = "mimo-key"

        let input = CloudASRValidationInput(platform: .xiaomiMiMoASR, asrConfig: config)

        XCTAssertTrue(input.isCloudPlatform)
        XCTAssertTrue(input.isComplete)
        XCTAssertEqual(input.fingerprint, "xiaomiMiMoASR\nmimo-key")
    }

    @MainActor
    func testSyncFromConfigRestoresXiaomiMiMoVerifiedState() throws {
        let store = ConfigStore(configDirectory: tempDirectory)
        var config = store.asrConfig
        config.selectedPlatform = .xiaomiMiMoASR
        config.xiaomiMiMo.apiKey = "mimo-key"
        try store.saveASRConfig(config)
        try store.updateCloudValidationState(for: .xiaomiMiMoASR, status: .verified)

        let service = CloudASRValidationService(configStore: store)
        service.syncFromConfig(
            for: CloudASRValidationInput(platform: .xiaomiMiMoASR, asrConfig: store.asrConfig)
        )

        XCTAssertEqual(service.status, .ready)
        XCTAssertNil(service.lastErrorMessage)
    }

    @MainActor
    func testXiaomiMiMoValidationTransitionsToReadyAndPersistsState() async throws {
        let store = ConfigStore(configDirectory: tempDirectory)
        var config = store.asrConfig
        config.selectedPlatform = .xiaomiMiMoASR
        config.xiaomiMiMo.apiKey = "mimo-key"
        try store.saveASRConfig(config)

        let service = CloudASRValidationService(
            configStore: store,
            validatorFactory: { _ in
                StubCloudASRValidator {}
            }
        )

        service.validate(CloudASRValidationInput(platform: .xiaomiMiMoASR, asrConfig: store.asrConfig))

        await waitUntil { service.status == .ready }
        XCTAssertEqual(store.asrConfig.xiaomiMiMo.validationStatus, .verified)
        XCTAssertNil(store.asrConfig.xiaomiMiMo.lastValidationError)
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async {
        let start = ContinuousClock.now
        while ContinuousClock.now - start < timeout {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for condition")
    }
}

private struct StubCloudASRValidator: CloudASRValidating {
    let action: @Sendable () async throws -> Void

    init(action: @escaping @Sendable () async throws -> Void) {
        self.action = action
    }

    func validateCredentials() async throws {
        try await action()
    }
}

private final class ValidationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    func currentValue() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
