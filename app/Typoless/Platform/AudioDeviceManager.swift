import AVFoundation
import Foundation

@MainActor
@Observable
final class AudioDeviceManager {
    private(set) var devices: [AudioInputDevice] = []

    private let configStore: ConfigStore
    private var notificationObservers: [NSObjectProtocol] = []

    init(configStore: ConfigStore) {
        self.configStore = configStore
        refreshDevices()
        observeDeviceChanges()
    }

    var selectedDeviceID: String? {
        configStore.audioInputConfig.selectedDeviceID
    }

    var selectedDeviceName: String? {
        configStore.audioInputConfig.selectedDeviceName
    }

    var selectedDeviceIsAvailable: Bool {
        guard let selectedDeviceID else { return true }
        return devices.contains { $0.id == selectedDeviceID }
    }

    var activeDeviceIDForRecording: String? {
        guard let selectedDeviceID, selectedDeviceIsAvailable else { return nil }
        return selectedDeviceID
    }

    var menuSelectionID: String {
        if let selectedDeviceID, selectedDeviceIsAvailable {
            return selectedDeviceID
        }
        return Self.systemDefaultSelectionID
    }

    var systemDefaultDeviceDisplayName: String {
        AVCaptureDevice.default(for: .audio)?.localizedName ?? "当前选择输入设备"
    }

    static let systemDefaultSelectionID = "__typoless_system_default__"

    func refreshDevices() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )

        devices = discoverySession.devices
            .filter { !Self.isSystemDefaultAggregateDevice($0) }
            .map { AudioInputDevice(id: $0.uniqueID, name: $0.localizedName) }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

        if let selectedDeviceID, !devices.contains(where: { $0.id == selectedDeviceID }) {
            selectSystemDefault()
        }
    }

    func selectMenuItem(id: String) {
        refreshDevices()

        if id == Self.systemDefaultSelectionID {
            selectSystemDefault()
            return
        }

        guard let device = devices.first(where: { $0.id == id }) else {
            selectSystemDefault()
            return
        }

        selectDevice(device)
    }

    func selectSystemDefault() {
        try? configStore.saveAudioInputConfig(.systemDefault)
    }

    func selectDevice(_ device: AudioInputDevice) {
        let config = AudioInputConfig(
            selectedDeviceID: device.id,
            selectedDeviceName: device.name
        )
        try? configStore.saveAudioInputConfig(config)
    }

    func captureDeviceForRecording() -> AVCaptureDevice? {
        refreshDevices()

        if let activeDeviceIDForRecording {
            return AVCaptureDevice(uniqueID: activeDeviceIDForRecording)
        }

        return AVCaptureDevice.default(for: .audio)
    }

    private func observeDeviceChanges() {
        let connected = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDevices()
            }
        }

        let disconnected = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDevices()
            }
        }

        notificationObservers = [connected, disconnected]
    }

    private static func isSystemDefaultAggregateDevice(_ device: AVCaptureDevice) -> Bool {
        device.uniqueID.hasPrefix("CADefaultDeviceAggregate-")
            || device.localizedName.hasPrefix("CADefaultDeviceAggregate-")
    }
}
