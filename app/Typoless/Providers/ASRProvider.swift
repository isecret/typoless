import Foundation

/// 统一的 ASR Provider 协议，所有语音识别实现需遵循此接口
protocol ASRProvider: Sendable {
    /// 对音频数据执行语音识别，返回转写结果
    func recognize(audioData: Data) async throws -> TranscriptResult
}
