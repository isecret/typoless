import XCTest
@testable import Typoless

final class ASRConfigTests: XCTestCase {
    func testReadinessForEachPlatform() {
        var config = ASRConfig()

        config.selectedPlatform = .localSenseVoice
        XCTAssertFalse(config.isReady(localModelsAvailable: false))
        XCTAssertTrue(config.isReady(localModelsAvailable: true))

        config.selectedPlatform = .tencentCloudSentence
        config.tencentCloud.secretId = "id"
        config.tencentCloud.secretKey = "key"
        XCTAssertFalse(config.isReady(localModelsAvailable: false))
        config.tencentCloud.validationStatus = .verified
        XCTAssertTrue(config.isReady(localModelsAvailable: false))

        config.selectedPlatform = .aliyunSentence
        config.aliyun.accessKeyId = "ak"
        config.aliyun.accessKeySecret = "secret"
        config.aliyun.appKey = "app"
        XCTAssertFalse(config.isReady(localModelsAvailable: false))
        config.aliyun.validationStatus = .verified
        XCTAssertTrue(config.isReady(localModelsAvailable: false))

        config.selectedPlatform = .volcengineSentence
        config.volcengine.apiKey = "api-key"
        XCTAssertFalse(config.isReady(localModelsAvailable: false))
        config.volcengine.validationStatus = .verified
        XCTAssertTrue(config.isReady(localModelsAvailable: false))

        config.selectedPlatform = .xunfeiSentence
        config.xunfei.appID = "appid"
        config.xunfei.apiKey = "api-key"
        config.xunfei.apiSecret = "api-secret"
        XCTAssertFalse(config.isReady(localModelsAvailable: false))
        config.xunfei.validationStatus = .verified
        XCTAssertTrue(config.isReady(localModelsAvailable: false))

        config.selectedPlatform = .xiaomiMiMoASR
        config.xiaomiMiMo.apiKey = "mimo-key"
        XCTAssertFalse(config.isReady(localModelsAvailable: false))
        config.xiaomiMiMo.validationStatus = .verified
        XCTAssertTrue(config.isReady(localModelsAvailable: false))
    }

    func testNotReadyReasonMatchesPlatform() {
        var config = ASRConfig()

        config.selectedPlatform = .aliyunSentence
        XCTAssertEqual(
            config.notReadyReason(localModelsAvailable: false),
            "阿里云 ASR 配置不完整，请填写 AccessKey ID、AccessKey Secret 和 AppKey"
        )

        config.aliyun.accessKeyId = "ak"
        config.aliyun.accessKeySecret = "secret"
        config.aliyun.appKey = "app"
        XCTAssertEqual(
            config.notReadyReason(localModelsAvailable: false),
            "阿里云 ASR 尚未通过真实请求验证，请先在设置页完成验证"
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

        config.selectedPlatform = .xiaomiMiMoASR
        XCTAssertEqual(
            config.notReadyReason(localModelsAvailable: false),
            "小米 MiMo ASR 配置不完整，请填写 API Key"
        )
    }

    func testProviderFactoryRoutesToExpectedProviderType() {
        let runtimeManager = SenseVoiceRuntimeManager()
        let factory = ASRProviderFactory(runtimeManager: runtimeManager)

        var config = ASRConfig()
        config.selectedPlatform = .localSenseVoice
        let local = factory.makeProvider(for: config)
        XCTAssertEqual(String(describing: type(of: local)), "SenseVoiceASRProvider")

        config.selectedPlatform = .aliyunSentence
        let aliyun = factory.makeProvider(for: config)
        XCTAssertEqual(String(describing: type(of: aliyun)), "AliyunSentenceASRProvider")

        config.selectedPlatform = .volcengineSentence
        let volcengine = factory.makeProvider(for: config)
        XCTAssertEqual(String(describing: type(of: volcengine)), "VolcengineSentenceASRProvider")

        config.selectedPlatform = .xunfeiSentence
        let xunfei = factory.makeProvider(for: config)
        XCTAssertEqual(String(describing: type(of: xunfei)), "XunfeiSentenceASRProvider")

        config.selectedPlatform = .xiaomiMiMoASR
        let xiaomiMiMo = factory.makeProvider(for: config)
        XCTAssertEqual(String(describing: type(of: xiaomiMiMo)), "XiaomiMiMoASRProvider")
    }

    func testDecodingLegacyLocalASRValueMigratesToSenseVoice() throws {
        let data = Data(#"{"selectedPlatform":"localFunASR","local":{"modelStatus":"notDownloaded"}}"#.utf8)
        let decoded = try JSONDecoder().decode(ASRConfig.self, from: data)
        XCTAssertEqual(decoded.selectedPlatform, .localSenseVoice)
    }

    func testXiaomiMiMoLanguageNormalization() throws {
        XCTAssertEqual(XiaomiMiMoASRConfig.normalizedLanguage(" zh "), "zh")
        XCTAssertEqual(XiaomiMiMoASRConfig.normalizedLanguage("EN"), "en")
        XCTAssertEqual(XiaomiMiMoASRConfig.normalizedLanguage("ja"), "auto")

        let data = Data(#"{"apiKey":"key","language":"ja"}"#.utf8)
        let decoded = try JSONDecoder().decode(XiaomiMiMoASRConfig.self, from: data)
        XCTAssertEqual(decoded.language, "auto")
    }
}
