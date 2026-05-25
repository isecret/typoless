import Foundation

@MainActor
@Observable
final class CloudASRValidationService {
    typealias ValidatorFactory = @MainActor @Sendable (CloudASRValidationInput) throws -> any CloudASRValidating

    private let validatorFactory: ValidatorFactory
    private let configStore: ConfigStore

    private var validationTask: Task<Void, Never>?
    private var activeFingerprint: String?
    private var lastCompletedFingerprint: String?

    private(set) var status: CloudASRValidationDisplayStatus = .incomplete
    private(set) var lastErrorMessage: String?

    init(
        configStore: ConfigStore,
        validatorFactory: @escaping ValidatorFactory = CloudASRValidationService.defaultValidatorFactory
    ) {
        self.configStore = configStore
        self.validatorFactory = validatorFactory
    }

    func syncFromConfig(for input: CloudASRValidationInput) {
        guard input.isCloudPlatform else {
            cancelOngoingValidation()
            status = .incomplete
            lastErrorMessage = nil
            activeFingerprint = nil
            lastCompletedFingerprint = nil
            return
        }

        let cloudState = cloudState(for: input)
        if !cloudState.isComplete {
            status = .incomplete
            lastErrorMessage = nil
            activeFingerprint = nil
            lastCompletedFingerprint = nil
            return
        }

        activeFingerprint = nil

        switch cloudState.validationStatus {
        case .unvalidated:
            status = .incomplete
            lastErrorMessage = nil
            lastCompletedFingerprint = nil
        case .validating:
            status = .ready
            lastErrorMessage = nil
            lastCompletedFingerprint = input.fingerprint
        case .verified:
            status = .ready
            lastErrorMessage = nil
            lastCompletedFingerprint = input.fingerprint
        case .failed:
            status = .failed
            lastErrorMessage = cloudState.lastValidationError
            lastCompletedFingerprint = nil
        }
    }

    func validate(_ input: CloudASRValidationInput, force: Bool = false) {
        guard input.isCloudPlatform else {
            syncFromConfig(for: input)
            return
        }

        guard input.isComplete else {
            cancelOngoingValidation()
            status = .incomplete
            lastErrorMessage = nil
            activeFingerprint = nil
            lastCompletedFingerprint = nil
            return
        }

        let fingerprint = input.fingerprint
        if !force {
            if activeFingerprint == fingerprint {
                return
            }
            if lastCompletedFingerprint == fingerprint, status == .ready {
                return
            }
        }

        validationTask?.cancel()
        activeFingerprint = fingerprint
        status = .checking
        lastErrorMessage = nil

        let validatorFactory = self.validatorFactory
        let configStore = self.configStore

        validationTask = Task { [weak self] in
            do {
                try await MainActor.run {
                    try configStore.updateCloudValidationState(for: input.platform, status: .validating)
                }
                let validator = try validatorFactory(input)
                do {
                    try await validator.validateCredentials()
                } catch let error as TypolessError where error == .cloudASREmptyResponse {
                    // 鉴权成功但测试音频没有识别结果，仍视为配置验证通过。
                }

                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.activeFingerprint == fingerprint else { return }
                    try? configStore.updateCloudValidationState(for: input.platform, status: .verified)
                    self.activeFingerprint = nil
                    self.lastCompletedFingerprint = fingerprint
                    self.validationTask = nil
                    self.status = .ready
                    self.lastErrorMessage = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                let errorMessage = Self.errorMessage(from: error)
                await MainActor.run {
                    guard let self, self.activeFingerprint == fingerprint else { return }
                    try? configStore.updateCloudValidationState(
                        for: input.platform,
                        status: .failed,
                        error: errorMessage
                    )
                    self.activeFingerprint = nil
                    self.lastCompletedFingerprint = fingerprint
                    self.validationTask = nil
                    self.status = .failed
                    self.lastErrorMessage = errorMessage
                }
            }
        }
    }

    private func cancelOngoingValidation() {
        validationTask?.cancel()
        validationTask = nil
    }

    private func cloudState(for input: CloudASRValidationInput) -> any CloudASRConfigState {
        switch input.platform {
        case .localSenseVoice:
            return input.asrConfig.tencentCloud
        case .tencentCloudSentence:
            return input.asrConfig.tencentCloud
        case .aliyunSentence:
            return input.asrConfig.aliyun
        case .volcengineSentence:
            return input.asrConfig.volcengine
        case .xunfeiSentence:
            return input.asrConfig.xunfei
        }
    }

    private static func defaultValidatorFactory(input: CloudASRValidationInput) throws -> any CloudASRValidating {
        switch input.platform {
        case .localSenseVoice:
            throw TypolessError.asrPlatformNotReady(detail: "本地平台不需要云端验证")
        case .tencentCloudSentence:
            return TencentSentenceASRProvider(
                secretId: input.asrConfig.tencentCloud.secretId,
                secretKey: input.asrConfig.tencentCloud.secretKey
            )
        case .aliyunSentence:
            return AliyunSentenceASRProvider(
                accessKeyId: input.asrConfig.aliyun.accessKeyId,
                accessKeySecret: input.asrConfig.aliyun.accessKeySecret,
                appKey: input.asrConfig.aliyun.appKey
            )
        case .volcengineSentence:
            return VolcengineSentenceASRProvider(apiKey: input.asrConfig.volcengine.apiKey)
        case .xunfeiSentence:
            return XunfeiSentenceASRProvider(
                appID: input.asrConfig.xunfei.appID,
                apiKey: input.asrConfig.xunfei.apiKey,
                apiSecret: input.asrConfig.xunfei.apiSecret
            )
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
