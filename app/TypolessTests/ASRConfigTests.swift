import XCTest
@testable import Typoless

final class ASRConfigTests: XCTestCase {
    func testReadinessForEachPlatform() {
        var config = ASRConfig()

        config.selectedPlatform = .localFunASR
        XCTAssertFalse(config.isReady(localModelsAvailable: false))
        XCTAssertTrue(config.isReady(localModelsAvailable: true))

        config.selectedPlatform = .tencentCloudSentence
        config.tencentCloud.secretId = "id"
        config.tencentCloud.secretKey = "key"
        XCTAssertTrue(config.isReady(localModelsAvailable: false))

        config.selectedPlatform = .aliyunSentence
        config.aliyun.accessKeyId = "ak"
        config.aliyun.accessKeySecret = "secret"
        config.aliyun.appKey = "app"
        XCTAssertTrue(config.isReady(localModelsAvailable: false))

        config.selectedPlatform = .volcengineSentence
        config.volcengine.apiKey = "api-key"
        XCTAssertTrue(config.isReady(localModelsAvailable: false))

        config.selectedPlatform = .xunfeiSentence
        config.xunfei.appID = "appid"
        config.xunfei.apiKey = "api-key"
        config.xunfei.apiSecret = "api-secret"
        XCTAssertTrue(config.isReady(localModelsAvailable: false))
    }

    func testNotReadyReasonMatchesPlatform() {
        var config = ASRConfig()

        config.selectedPlatform = .aliyunSentence
        XCTAssertEqual(
            config.notReadyReason(localModelsAvailable: false),
            "阿里云 ASR 配置不完整，请填写 AccessKey ID、AccessKey Secret 和 AppKey"
        )

        config.selectedPlatform = .volcengineSentence
        XCTAssertEqual(
            config.notReadyReason(localModelsAvailable: false),
            "火山引擎 ASR 配置不完整，请填写 API Key"
        )

        config.selectedPlatform = .xunfeiSentence
        XCTAssertEqual(
            config.notReadyReason(localModelsAvailable: false),
            "科大讯飞 ASR 配置不完整，请填写 AppID、API Key 和 API Secret"
        )
    }

    func testProviderFactoryRoutesToExpectedProviderType() {
        let runtimeManager = ASRRuntimeManager()
        let factory = ASRProviderFactory(runtimeManager: runtimeManager)

        var config = ASRConfig()
        config.selectedPlatform = .aliyunSentence
        let aliyun = factory.makeProvider(for: config, hotwords: "")
        XCTAssertEqual(String(describing: type(of: aliyun)), "AliyunSentenceASRProvider")

        config.selectedPlatform = .volcengineSentence
        let volcengine = factory.makeProvider(for: config, hotwords: "")
        XCTAssertEqual(String(describing: type(of: volcengine)), "VolcengineSentenceASRProvider")

        config.selectedPlatform = .xunfeiSentence
        let xunfei = factory.makeProvider(for: config, hotwords: "")
        XCTAssertEqual(String(describing: type(of: xunfei)), "XunfeiSentenceASRProvider")
    }
}
