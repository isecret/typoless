import Foundation
import XCTest
@testable import Typoless

final class ConfigStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    @MainActor
    func testLoadLegacyASRShapeKeepsNewPlatformsAtDefault() throws {
        let configURL = tempDirectory.appendingPathComponent("config.json")
        let legacyJSON = """
        {
          "asr" : {
            "selectedPlatform" : "tencentCloudSentence",
            "tencentCloud" : {
              "secretId" : "legacy-id",
              "secretKey" : "legacy-key"
            }
          },
          "general" : {
            "hotkey" : {
              "displayString" : "⌥ Space",
              "keyCode" : 49,
              "modifiers" : 524576
            }
          },
          "llm" : {
            "apiKey" : "",
            "baseURL" : "",
            "model" : "",
            "thinkingDisabled" : false
          }
        }
        """
        try legacyJSON.write(to: configURL, atomically: true, encoding: .utf8)

        let store = ConfigStore(configDirectory: tempDirectory)

        XCTAssertEqual(store.asrConfig.selectedPlatform, .tencentCloudSentence)
        XCTAssertEqual(store.asrConfig.tencentCloud.secretId, "legacy-id")
        XCTAssertEqual(store.asrConfig.tencentCloud.secretKey, "legacy-key")
        XCTAssertEqual(store.asrConfig.aliyun.accessKeyId, "")
        XCTAssertEqual(store.asrConfig.volcengine.apiKey, "")
        XCTAssertEqual(store.asrConfig.xunfei.appID, "")
        XCTAssertTrue(store.generalConfig.interactionSoundEnabled)
    }

    @MainActor
    func testSaveAndReloadNewCloudASRConfig() throws {
        let firstStore = ConfigStore(configDirectory: tempDirectory)
        var asrConfig = firstStore.asrConfig
        asrConfig.selectedPlatform = .volcengineSentence
        asrConfig.volcengine.apiKey = "volc-key"
        asrConfig.aliyun.accessKeyId = "ak"
        asrConfig.aliyun.accessKeySecret = "secret"
        asrConfig.aliyun.appKey = "app"
        try firstStore.saveASRConfig(asrConfig)

        let secondStore = ConfigStore(configDirectory: tempDirectory)
        XCTAssertEqual(secondStore.asrConfig.selectedPlatform, .volcengineSentence)
        XCTAssertEqual(secondStore.asrConfig.volcengine.apiKey, "volc-key")
        XCTAssertEqual(secondStore.asrConfig.aliyun.accessKeyId, "ak")
        XCTAssertEqual(secondStore.asrConfig.aliyun.accessKeySecret, "secret")
        XCTAssertEqual(secondStore.asrConfig.aliyun.appKey, "app")
    }

    @MainActor
    func testSaveAndReloadGeneralConfigPersistsInteractionSoundEnabled() throws {
        let firstStore = ConfigStore(configDirectory: tempDirectory)
        let config = GeneralConfig(
            hotkey: .default,
            interactionSoundEnabled: false
        )
        try firstStore.saveGeneralConfig(config)

        let secondStore = ConfigStore(configDirectory: tempDirectory)
        XCTAssertFalse(secondStore.generalConfig.interactionSoundEnabled)
    }
}
