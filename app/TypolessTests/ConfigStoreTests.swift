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
        XCTAssertEqual(store.asrConfig.xiaomiMiMo.apiKey, "")
        XCTAssertEqual(store.asrConfig.xiaomiMiMo.language, "auto")
        XCTAssertTrue(store.generalConfig.interactionSoundEnabled)
        XCTAssertEqual(store.generalConfig.hotkey.displayString, "⌥ + Space")
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
        asrConfig.xiaomiMiMo.apiKey = "mimo-key"
        asrConfig.xiaomiMiMo.language = "zh"
        try firstStore.saveASRConfig(asrConfig)
        try firstStore.updateCloudValidationState(for: .volcengineSentence, status: .verified)
        try firstStore.updateCloudValidationState(for: .xiaomiMiMoASR, status: .verified)

        let secondStore = ConfigStore(configDirectory: tempDirectory)
        XCTAssertEqual(secondStore.asrConfig.selectedPlatform, .volcengineSentence)
        XCTAssertEqual(secondStore.asrConfig.volcengine.apiKey, "volc-key")
        XCTAssertEqual(secondStore.asrConfig.volcengine.validationStatus, .verified)
        XCTAssertEqual(secondStore.asrConfig.aliyun.accessKeyId, "ak")
        XCTAssertEqual(secondStore.asrConfig.aliyun.accessKeySecret, "secret")
        XCTAssertEqual(secondStore.asrConfig.aliyun.appKey, "app")
        XCTAssertEqual(secondStore.asrConfig.xiaomiMiMo.apiKey, "mimo-key")
        XCTAssertEqual(secondStore.asrConfig.xiaomiMiMo.language, "zh")
        XCTAssertEqual(secondStore.asrConfig.xiaomiMiMo.validationStatus, .verified)
    }

    @MainActor
    func testChangingCloudCredentialsInvalidatesValidationState() throws {
        let store = ConfigStore(configDirectory: tempDirectory)
        var asrConfig = store.asrConfig
        asrConfig.selectedPlatform = .tencentCloudSentence
        asrConfig.tencentCloud.secretId = "secret-id"
        asrConfig.tencentCloud.secretKey = "secret-key"
        try store.saveASRConfig(asrConfig)
        try store.updateCloudValidationState(for: .tencentCloudSentence, status: .verified)

        var changedConfig = store.asrConfig
        changedConfig.tencentCloud.secretKey = "new-secret-key"
        try store.saveASRConfig(changedConfig)

        XCTAssertEqual(store.asrConfig.tencentCloud.validationStatus, .unvalidated)
        XCTAssertNil(store.asrConfig.tencentCloud.lastValidationError)
    }

    @MainActor
    func testChangingXiaomiMiMoLanguageInvalidatesValidationState() throws {
        let store = ConfigStore(configDirectory: tempDirectory)
        var asrConfig = store.asrConfig
        asrConfig.selectedPlatform = .xiaomiMiMoASR
        asrConfig.xiaomiMiMo.apiKey = "mimo-key"
        asrConfig.xiaomiMiMo.language = "auto"
        try store.saveASRConfig(asrConfig)
        try store.updateCloudValidationState(for: .xiaomiMiMoASR, status: .verified)

        var changedConfig = store.asrConfig
        changedConfig.xiaomiMiMo.language = "zh"
        try store.saveASRConfig(changedConfig)

        XCTAssertEqual(store.asrConfig.xiaomiMiMo.validationStatus, .unvalidated)
        XCTAssertNil(store.asrConfig.xiaomiMiMo.lastValidationError)
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

    @MainActor
    func testSaveAndReloadSpecialHotkeyConfig() throws {
        let firstStore = ConfigStore(configDirectory: tempDirectory)
        let specialHotkey = HotkeyCombo.special(
            modifiers: [
                HotkeyModifierSpec(key: .command, side: .right),
                HotkeyModifierSpec(key: .option, side: .left),
            ]
        )

        try firstStore.saveGeneralConfig(
            GeneralConfig(
                hotkey: specialHotkey,
                interactionSoundEnabled: true
            )
        )

        let secondStore = ConfigStore(configDirectory: tempDirectory)
        XCTAssertEqual(secondStore.generalConfig.hotkey, specialHotkey)
    }

    @MainActor
    func testMissingAudioInputConfigDefaultsToSystemDefault() throws {
        let configURL = tempDirectory.appendingPathComponent("config.json")
        let legacyJSON = """
        {
          "asr" : {},
          "general" : {
            "hotkey" : {
              "displayString" : "⌥ Space",
              "keyCode" : 49,
              "modifiers" : 524576
            },
            "interactionSoundEnabled" : true
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

        XCTAssertTrue(store.audioInputConfig.usesSystemDefault)
        XCTAssertNil(store.audioInputConfig.selectedDeviceID)
        XCTAssertNil(store.audioInputConfig.selectedDeviceName)
    }

    @MainActor
    func testSaveAndReloadAudioInputConfig() throws {
        let firstStore = ConfigStore(configDirectory: tempDirectory)
        let config = AudioInputConfig(
            selectedDeviceID: "device-1",
            selectedDeviceName: "Studio Display 麦克风"
        )
        try firstStore.saveAudioInputConfig(config)

        let secondStore = ConfigStore(configDirectory: tempDirectory)
        XCTAssertEqual(secondStore.audioInputConfig, config)
    }

    @MainActor
    func testLoadLegacyAutomaticUpdateChecksPreferenceForSparkleMigration() throws {
        let configURL = tempDirectory.appendingPathComponent("config.json")
        let legacyJSON = """
        {
          "asr" : {},
          "general" : {
            "automaticUpdateChecksEnabled" : false,
            "hotkey" : {
              "displayString" : "⌥ Space",
              "keyCode" : 49,
              "modifiers" : 524576
            },
            "interactionSoundEnabled" : true
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

        XCTAssertFalse(store.legacyAutomaticUpdateChecksEnabled ?? true)
        XCTAssertEqual(
            store.generalConfig,
            GeneralConfig(
                hotkey: .default,
                interactionSoundEnabled: true
            )
        )
    }

    @MainActor
    func testSaveGeneralConfigDropsLegacyAutomaticUpdateChecksField() throws {
        let configURL = tempDirectory.appendingPathComponent("config.json")
        let legacyJSON = """
        {
          "asr" : {},
          "general" : {
            "automaticUpdateChecksEnabled" : false,
            "hotkey" : {
              "displayString" : "⌥ Space",
              "keyCode" : 49,
              "modifiers" : 524576
            },
            "interactionSoundEnabled" : true
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
        try store.saveGeneralConfig(GeneralConfig(hotkey: .default, interactionSoundEnabled: false))

        let savedJSON = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertFalse(savedJSON.contains("automaticUpdateChecksEnabled"))
    }
}
