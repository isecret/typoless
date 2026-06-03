import Foundation

struct ASRProviderFactory {
    let runtimeManager: SenseVoiceRuntimeManager

    func makeProvider(for config: ASRConfig) -> any ASRProvider {
        switch config.selectedPlatform {
        case .localSenseVoice:
            SenseVoiceASRProvider(runtimeManager: runtimeManager)
        case .tencentCloudSentence:
            TencentSentenceASRProvider(
                secretId: config.tencentCloud.secretId,
                secretKey: config.tencentCloud.secretKey
            )
        case .aliyunSentence:
            AliyunSentenceASRProvider(
                accessKeyId: config.aliyun.accessKeyId,
                accessKeySecret: config.aliyun.accessKeySecret,
                appKey: config.aliyun.appKey
            )
        case .volcengineSentence:
            VolcengineSentenceASRProvider(apiKey: config.volcengine.apiKey)
        case .xunfeiSentence:
            XunfeiSentenceASRProvider(
                appID: config.xunfei.appID,
                apiKey: config.xunfei.apiKey,
                apiSecret: config.xunfei.apiSecret
            )
        case .xiaomiMiMoASR:
            XiaomiMiMoASRProvider(
                apiKey: config.xiaomiMiMo.apiKey,
                language: config.xiaomiMiMo.language
            )
        }
    }
}
