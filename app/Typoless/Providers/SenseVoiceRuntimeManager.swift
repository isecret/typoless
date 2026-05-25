import Foundation
import os.log

final class SenseVoiceRuntimeManager: @unchecked Sendable {
    enum WarmupState: Sendable {
        case cold
        case warming
        case warm
    }

    private struct AudioSamples: @unchecked Sendable {
        let values: [Float]
        let sampleRate: Int32
    }

    private final class StringContinuationGate: @unchecked Sendable {
        private let lock = NSLock()
        private var didResume = false

        func resumeSuccess(_ continuation: CheckedContinuation<String, Error>, value: String) {
            lock.lock()
            defer { lock.unlock() }
            guard !didResume else { return }
            didResume = true
            continuation.resume(returning: value)
        }

        func resumeFailure(_ continuation: CheckedContinuation<String, Error>, error: Error) {
            lock.lock()
            defer { lock.unlock() }
            guard !didResume else { return }
            didResume = true
            continuation.resume(throwing: error)
        }
    }

    private let logger = Logger(subsystem: "com.isecret.typoless", category: "SenseVoice")
    private let queue = DispatchQueue(label: "com.isecret.typoless.sensevoice", qos: .userInitiated)
    private let lock = NSLock()

    private var recognizer: OpaquePointer?
    private var warmupTask: Task<Void, Error>?
    private(set) var warmupState: WarmupState = .cold

    deinit {
        invalidateCurrentRecognizer()
    }

    var isWarm: Bool {
        lock.withLock { warmupState == .warm }
    }

    @discardableResult
    func warmup() -> Task<Void, Error> {
        lock.lock()
        defer { lock.unlock() }

        if warmupState == .warm, recognizer != nil {
            return Task { }
        }
        if let warmupTask {
            return warmupTask
        }

        let task = Task { [weak self] in
            guard let self else { return }
            _ = try await self.loadRecognizer()
        }
        warmupTask = task
        warmupState = .warming
        return task
    }

    func awaitWarmupIfNeeded() async throws {
        let task = lock.withLock { warmupTask }
        if let task {
            try await task.value
        }
    }

    func recognize(samples: [Float], sampleRate: Int32, timeout: TimeInterval) async throws -> String {
        let audio = AudioSamples(values: samples, sampleRate: sampleRate)
        return try await withCheckedThrowingContinuation { continuation in
            let gate = StringContinuationGate()

            queue.async { [weak self] in
                guard let self else {
                    gate.resumeFailure(continuation, error: TypolessError.asrProcessFailure(message: "SenseVoice runtime released"))
                    return
                }

                do {
                    let recognizer = try self.loadRecognizerSync()
                    let text = try self.recognizeSync(recognizer: recognizer, audio: audio)
                    gate.resumeSuccess(continuation, value: text)
                } catch {
                    gate.resumeFailure(continuation, error: error)
                }
            }

            Task.detached {
                try? await Task.sleep(for: .seconds(timeout))
                gate.resumeFailure(
                    continuation,
                    error: TypolessError.asrProcessFailure(message: "ASR timeout after \(Int(timeout))s")
                )
            }
        }
    }

    func markRecognitionSucceeded() {
        // Kept for parity with the previous runtime manager. SenseVoice stays warm
        // until app exit or explicit invalidation.
    }

    func invalidateCurrentRecognizer() {
        queue.async { [weak self] in
            guard let self else { return }
            let handle = self.lock.withLock { () -> OpaquePointer? in
                let current = recognizer
                recognizer = nil
                warmupTask?.cancel()
                warmupTask = nil
                warmupState = .cold
                return current
            }
            if let handle {
                TypolessSherpaDestroyRecognizer(handle)
            }
        }
    }

    func invalidateCurrentWorker() {
        invalidateCurrentRecognizer()
    }

    private func loadRecognizer() async throws -> OpaquePointer {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: TypolessError.asrProcessFailure(message: "SenseVoice runtime released"))
                    return
                }
                do {
                    continuation.resume(returning: try self.loadRecognizerSync())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func loadRecognizerSync() throws -> OpaquePointer {
        if let existing = lock.withLock({ recognizer }) {
            return existing
        }

        let resourceRoot = ResourceValidator.sherpaOnnxResourceRoot()
        let libraryPath = resourceRoot.appendingPathComponent("lib/libsherpa-onnx-c-api.dylib").path
        let modelPath = LocalASRConfig.modelRoot.appendingPathComponent(LocalASRConfig.modelFileName).path
        let tokensPath = LocalASRConfig.modelRoot.appendingPathComponent(LocalASRConfig.tokensFileName).path

        try withBridgeError { errorBuffer, errorSize in
            TypolessSherpaLoadLibrary(libraryPath, errorBuffer, errorSize) == 1
        }

        let handle = try withBridgeError { errorBuffer, errorSize in
            TypolessSherpaCreateRecognizer(
                modelPath,
                tokensPath,
                "zh",
                1,
                2,
                errorBuffer,
                errorSize
            )
        }

        lock.withLock {
            recognizer = handle
            warmupState = .warm
            warmupTask = nil
        }

        logger.info("SenseVoice warmup completed, sherpa-onnx=\(String(cString: TypolessSherpaVersion()), privacy: .public)")
        return handle
    }

    private func recognizeSync(recognizer: OpaquePointer, audio: AudioSamples) throws -> String {
        try audio.values.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                throw TypolessError.asrEmptyAudio
            }

            let textPointer = try withBridgeError { errorBuffer, errorSize in
                TypolessSherpaRecognize(
                    recognizer,
                    baseAddress,
                    Int32(buffer.count),
                    audio.sampleRate,
                    errorBuffer,
                    errorSize
                )
            }
            defer { TypolessSherpaFreeString(textPointer) }
            return String(cString: textPointer)
        }
    }

    private func withBridgeError(_ body: (UnsafeMutablePointer<CChar>, Int32) -> Bool) throws {
        var errorBuffer = [CChar](repeating: 0, count: 1024)
        let ok = errorBuffer.withUnsafeMutableBufferPointer { buffer in
            body(buffer.baseAddress!, Int32(buffer.count))
        }
        if !ok {
            let message = String(cString: errorBuffer)
            throw TypolessError.asrProcessFailure(message: message.isEmpty ? "SenseVoice runtime failure" : message)
        }
    }

    private func withBridgeError<T>(_ body: (UnsafeMutablePointer<CChar>, Int32) -> T?) throws -> T {
        var errorBuffer = [CChar](repeating: 0, count: 1024)
        let value = errorBuffer.withUnsafeMutableBufferPointer { buffer in
            body(buffer.baseAddress!, Int32(buffer.count))
        }
        guard let value else {
            let message = String(cString: errorBuffer)
            throw TypolessError.asrProcessFailure(message: message.isEmpty ? "SenseVoice runtime failure" : message)
        }
        return value
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
