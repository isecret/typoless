import Foundation

/// 统一的 ASR Provider 协议，所有语音识别实现需遵循此接口
protocol ASRProvider: Sendable {
    /// 对音频数据执行语音识别，返回转写结果
    func recognize(audioData: Data) async throws -> TranscriptResult
}

/// 流式 ASR 事件
enum StreamingASREvent: Sendable {
    case partial(text: String)
    case final_(result: TranscriptResult)
}

/// 流式 ASR Provider 协议，支持 partial/final 事件
protocol StreamingASRCapable: ASRProvider {
    /// 接受音频 chunk 进行流式识别
    func feedAudioChunk(_ chunk: Data) throws

    /// 结束音频输入，等待最终结果
    func finishAndGetFinal() async throws -> TranscriptResult

    /// 重置识别状态
    func reset()
}
