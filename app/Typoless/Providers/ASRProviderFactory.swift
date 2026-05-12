import Foundation

struct ASRProviderFactory {
    let runtimeManager: ASRRuntimeManager

    func makeProvider(
        for config: ASRConfig,
        hotwords: String
    ) -> any ASRProvider {
        switch config.selectedPlatform {
        case .localFunASR:
            FunASRProvider(runtimeManager: runtimeManager, hotwords: hotwords)
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
        }
    }
}
