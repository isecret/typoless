import Foundation
import os

/// 主链路诊断日志器，使用 macOS Unified Logging 记录各阶段耗时与结果摘要
///
/// - Debug 构建：输出 ASR 原文与 LLM 输出明文对照
/// - Release 构建：仅输出长度、hash、来源等脱敏摘要
final class DiagnosticsLogger: Sendable {

    static let shared = DiagnosticsLogger()

    private let logger = Logger(
        subsystem: "com.isecret.typoless",
        category: "Session"
    )

    private init() {}

    // MARK: - Session Lifecycle

    func sessionStarted(sessionID: String, targetBundleID: String?) {
        logger.info(
            "[\(sessionID)] session_started | target=\(targetBundleID ?? "unknown", privacy: .public)"
        )
    }

    func sessionEnded(
        sessionID: String,
        result: SessionDiagnostics
    ) {
        let source = result.resultSource ?? "none"
        let errorType = result.errorClassification ?? "none"

        logger.info(
            """
            [\(sessionID)] session_ended \
            | recording=\(result.recordingMs)ms \
            | denoise=\(result.denoiseMs ?? -1)ms \
            | asr=\(result.asrMs ?? -1)ms \
            | llm=\(result.llmMs ?? -1)ms \
            | injection=\(result.injectionMs ?? -1)ms \
            | total=\(result.totalMs)ms \
            | source=\(source, privacy: .public) \
            | error=\(errorType, privacy: .public) \
            | target=\(result.targetBundleID ?? "unknown", privacy: .public)
            """
        )
    }

    // MARK: - Short Recording Cancelled

    func shortRecordingCancelled(sessionID: String, durationMs: Int) {
        logger.info(
            "[\(sessionID)] short_recording_cancelled | duration=\(durationMs)ms"
        )
    }

    // MARK: - ASR/LLM Comparison

    func asrCompleted(sessionID: String, text: String, durationMs: Int, coldStart: Bool = false, warmupWaitMs: Int = 0) {
        #if DEBUG
        logger.debug(
            "[\(sessionID)] asr_completed | text=\"\(text, privacy: .public)\" | duration=\(durationMs)ms | cold_start=\(coldStart) | warmup_wait=\(warmupWaitMs)ms"
        )
        #else
        let hash = Self.textHash(text)
        logger.info(
            "[\(sessionID)] asr_completed | length=\(text.count) | hash=\(hash, privacy: .public) | duration=\(durationMs)ms | cold_start=\(coldStart) | warmup_wait=\(warmupWaitMs)ms"
        )
        #endif
    }

    func llmCompleted(sessionID: String, text: String, source: String, durationMs: Int) {
        #if DEBUG
        logger.debug(
            "[\(sessionID)] llm_completed | text=\"\(text, privacy: .public)\" | source=\(source, privacy: .public) | duration=\(durationMs)ms"
        )
        #else
        let hash = Self.textHash(text)
        logger.info(
            "[\(sessionID)] llm_completed | length=\(text.count) | hash=\(hash, privacy: .public) | source=\(source, privacy: .public) | duration=\(durationMs)ms"
        )
        #endif
    }

    // MARK: - Error Logging

    func sessionError(sessionID: String, error: TypolessError) {
        logger.error(
            "[\(sessionID)] session_error | type=\(error.diagnosticClassification, privacy: .public)"
        )
    }

    func sessionCancelled(sessionID: String) {
        logger.info("[\(sessionID)] session_cancelled")
    }

    // MARK: - Denoising

    func denoiseCompleted(sessionID: String, durationMs: Int) {
        logger.info(
            "[\(sessionID)] denoise_completed | duration=\(durationMs)ms"
        )
    }

    func denoiseFailed(sessionID: String, reason: String) {
        logger.error(
            "[\(sessionID)] denoise_failed | reason=\(reason, privacy: .public)"
        )
    }

    // MARK: - General Events

    func log(sessionID: String, event: String, detail: String? = nil) {
        if let detail {
            logger.info("[\(sessionID)] \(event, privacy: .public) | detail=\(detail, privacy: .public)")
        } else {
            logger.info("[\(sessionID)] \(event, privacy: .public)")
        }
    }

    // MARK: - Helpers

    private static func textHash(_ text: String) -> String {
        var hasher = Hasher()
        hasher.combine(text)
        let hash = hasher.finalize()
        return String(format: "%08x", abs(hash))
    }
}

// MARK: - Session Diagnostics Data

struct SessionDiagnostics: Sendable {
    var recordingMs: Int = 0
    var denoiseMs: Int?
    var asrMs: Int?
    var llmMs: Int?
    var injectionMs: Int?
    var totalMs: Int = 0
    var resultSource: String?
    var errorClassification: String?
    var targetBundleID: String?
}

// MARK: - TypolessError Diagnostic Classification

extension TypolessError {
    /// 用于诊断日志的错误分类标识，不含用户文本或敏感信息
    var diagnosticClassification: String {
        switch self {
        case .microphonePermissionDenied: "microphone_permission_denied"
        case .accessibilityPermissionDenied: "accessibility_permission_denied"
        case .asrEmptyAudio: "asr_empty_audio"
        case .asrPlatformNotReady: "asr_platform_not_ready"
        case .asrBinaryNotFound: "asr_binary_not_found"
        case .asrModelMissing: "asr_model_missing"
        case .asrRuntimeMissing: "asr_runtime_missing"
        case .asrProcessFailure: "asr_process_failure"
        case .audioPreprocessFailure: "audio_preprocess_failure"
        case .cloudASRConfigurationIncomplete: "cloud_asr_configuration_incomplete"
        case .cloudASRAuthenticationFailure: "cloud_asr_authentication_failure"
        case .cloudASRNetworkFailure: "cloud_asr_network_failure"
        case .cloudASREmptyResponse: "cloud_asr_empty_response"
        case .cloudASRInvalidResponse: "cloud_asr_invalid_response"
        case .llmConfigurationIncomplete: "llm_configuration_incomplete"
        case .invalidLLMConfiguration: "invalid_llm_configuration"
        case .llmNetworkFailure: "llm_network_failure"
        case .llmEmptyResponse: "llm_empty_response"
        case .textInjectionFailure: "text_injection_failure"
        case .sessionCancelled: "session_cancelled"
        }
    }
}
