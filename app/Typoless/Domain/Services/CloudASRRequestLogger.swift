import Foundation
import os

struct CloudASRRequestMetrics: Sendable {
    let provider: String
    let endpoint: String
    let transport: String
    let audioBytes: Int
    let uploadBytes: Int
    let timeoutMs: Int
    let base64Bytes: Int?
    let frameCount: Int?
    let minFrameBytes: Int?
    let maxFrameBytes: Int?
    let extra: String?
}

enum CloudASRRequestLogger {
    private static let logger = Logger(
        subsystem: "com.isecret.typoless",
        category: "CloudASR"
    )

    static func requestPrepared(_ metrics: CloudASRRequestMetrics) {
        var fields = [
            "provider=\(metrics.provider)",
            "endpoint=\(metrics.endpoint)",
            "transport=\(metrics.transport)",
            "audio_bytes=\(metrics.audioBytes)",
            "upload_bytes=\(metrics.uploadBytes)",
            "timeout=\(metrics.timeoutMs)ms",
        ]

        if let base64Bytes = metrics.base64Bytes {
            fields.append("base64_bytes=\(base64Bytes)")
        }

        if let frameCount = metrics.frameCount {
            fields.append("frame_count=\(frameCount)")
        }

        if let minFrameBytes = metrics.minFrameBytes {
            fields.append("min_frame_bytes=\(minFrameBytes)")
        }

        if let maxFrameBytes = metrics.maxFrameBytes {
            fields.append("max_frame_bytes=\(maxFrameBytes)")
        }

        if let extra = metrics.extra, !extra.isEmpty {
            fields.append(extra)
        }

        logger.info("request_prepared | \(fields.joined(separator: " | "), privacy: .public)")
    }

    static func requestCompleted(
        provider: String,
        endpoint: String,
        durationMs: Int,
        responseBytes: Int,
        statusCode: Int?,
        requestID: String?
    ) {
        var fields = [
            "provider=\(provider)",
            "endpoint=\(endpoint)",
            "duration=\(durationMs)ms",
            "response_bytes=\(responseBytes)",
            "status=\(statusCode ?? -1)",
        ]

        if let requestID, !requestID.isEmpty {
            fields.append("request_id=\(requestID)")
        }

        logger.info("request_completed | \(fields.joined(separator: " | "), privacy: .public)")
    }

    static func requestFailed(
        provider: String,
        endpoint: String,
        phase: String,
        statusCode: Int? = nil,
        message: String
    ) {
        var fields = [
            "provider=\(provider)",
            "endpoint=\(endpoint)",
            "phase=\(phase)",
        ]

        if let statusCode {
            fields.append("status=\(statusCode)")
        }

        fields.append("message=\(message)")

        logger.error("request_failed | \(fields.joined(separator: " | "), privacy: .public)")
    }
}
