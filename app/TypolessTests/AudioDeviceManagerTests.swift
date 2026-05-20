import XCTest
@testable import Typoless

final class AudioDeviceManagerTests: XCTestCase {
    func testSystemDefaultAggregateDevicePrefixesAreHidden() {
        XCTAssertTrue(AudioDeviceManager.isSystemDefaultAggregateDeviceID(
            "CADefaultDeviceAggregate-1",
            localizedName: "系统默认"
        ))
        XCTAssertTrue(AudioDeviceManager.isSystemDefaultAggregateDeviceID(
            "input-1",
            localizedName: "ICADefaultDeviceAggregate-14713-4"
        ))
        XCTAssertFalse(AudioDeviceManager.isSystemDefaultAggregateDeviceID(
            "BuiltInMicrophoneDevice",
            localizedName: "MacBook Pro 麦克风"
        ))
    }

    func testSystemDefaultDisplayNameShowsNoMicrophoneForAggregateWithoutDevices() {
        let displayName = AudioDeviceManager.systemDefaultDeviceDisplayName(
            defaultDeviceID: "ICADefaultDeviceAggregate-14713-4",
            defaultDeviceName: "ICADefaultDeviceAggregate-14713-4",
            availableDevices: []
        )

        XCTAssertEqual(displayName, "未找到可用麦克风")
    }

    func testSystemDefaultDisplayNameFallsBackToAvailableMicrophoneForAggregate() {
        let displayName = AudioDeviceManager.systemDefaultDeviceDisplayName(
            defaultDeviceID: "CADefaultDeviceAggregate-1",
            defaultDeviceName: "CADefaultDeviceAggregate-1",
            availableDevices: [
                AudioInputDevice(id: "studio-display", name: "Studio Display 麦克风"),
            ]
        )

        XCTAssertEqual(displayName, "Studio Display 麦克风")
    }

    func testSystemDefaultDisplayNameKeepsHumanReadableDefaultName() {
        let displayName = AudioDeviceManager.systemDefaultDeviceDisplayName(
            defaultDeviceID: "built-in",
            defaultDeviceName: "MacBook Pro 麦克风",
            availableDevices: []
        )

        XCTAssertEqual(displayName, "MacBook Pro 麦克风")
    }

    func testSystemDefaultMenuTitleShowsNoMicrophoneDirectly() {
        XCTAssertEqual(
            AudioDeviceManager.systemDefaultMenuItemTitle(displayName: AudioDeviceManager.noInputDeviceDisplayName),
            AudioDeviceManager.noInputDeviceDisplayName
        )
    }

    func testSystemDefaultMenuTitleIncludesDefaultDeviceName() {
        XCTAssertEqual(
            AudioDeviceManager.systemDefaultMenuItemTitle(displayName: "MacBook Pro 麦克风"),
            "系统默认(MacBook Pro 麦克风)"
        )
    }
}
