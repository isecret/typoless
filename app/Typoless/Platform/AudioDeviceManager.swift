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
        guard let defaultDevice = AVCaptureDevice.default(for: .audio) else {
            return Self.systemDefaultDeviceDisplayName(
                defaultDeviceID: nil,
                defaultDeviceName: nil,
                availableDevices: devices
            )
        }

        return Self.systemDefaultDeviceDisplayName(
            defaultDeviceID: defaultDevice.uniqueID,
            defaultDeviceName: defaultDevice.localizedName,
            availableDevices: devices
        )
    }

    var systemDefaultMenuItemTitle: String {
        Self.systemDefaultMenuItemTitle(displayName: systemDefaultDeviceDisplayName)
    }

    var hasAvailableInputDevice: Bool {
        systemDefaultDeviceDisplayName != Self.noInputDeviceDisplayName
    }

    nonisolated static let systemDefaultSelectionID = "__typoless_system_default__"
    nonisolated static let noInputDeviceDisplayName = "未找到可用麦克风"

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

    nonisolated static func systemDefaultDeviceDisplayName(
        defaultDeviceID: String?,
        defaultDeviceName: String?,
        availableDevices: [AudioInputDevice]
    ) -> String {
        let trimmedName = defaultDeviceName?.trimmingCharacters(in: .whitespacesAndNewlines)

        if isSystemDefaultAggregateDeviceID(defaultDeviceID, localizedName: trimmedName) {
            return availableDevices.first?.name ?? noInputDeviceDisplayName
        }

        if let trimmedName, !trimmedName.isEmpty {
            return trimmedName
        }

        return availableDevices.first?.name ?? noInputDeviceDisplayName
    }

    nonisolated static func systemDefaultMenuItemTitle(displayName: String) -> String {
        if displayName == noInputDeviceDisplayName {
            return displayName
        }

        return "系统默认(\(displayName))"
    }

    nonisolated static func isSystemDefaultAggregateDeviceID(
        _ uniqueID: String?,
        localizedName: String?
    ) -> Bool {
        let prefixes = [
            "CADefaultDeviceAggregate-",
            "ICADefaultDeviceAggregate-",
        ]

        return prefixes.contains { prefix in
            uniqueID?.hasPrefix(prefix) == true
                || localizedName?.hasPrefix(prefix) == true
        }
    }

    private static func isSystemDefaultAggregateDevice(_ device: AVCaptureDevice) -> Bool {
        isSystemDefaultAggregateDeviceID(device.uniqueID, localizedName: device.localizedName)
    }
}
