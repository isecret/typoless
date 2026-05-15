import Foundation
import Observation
import Sparkle

@MainActor
@Observable
final class AppUpdateService {
    private enum DefaultsKey {
        static let automaticChecksMigrated = "typoless.sparkleAutomaticChecksMigrated"
    }

    @ObservationIgnored
    private let configStore: ConfigStore

    @ObservationIgnored
    private let userDefaults: UserDefaults

    @ObservationIgnored
    private let updaterController: SPUStandardUpdaterController

    @ObservationIgnored
    private var automaticChecksObservation: NSKeyValueObservation?

    @ObservationIgnored
    private var canCheckObservation: NSKeyValueObservation?

    @ObservationIgnored
    private var didStart = false

    private(set) var automaticallyChecksForUpdates: Bool
    private(set) var canCheckForUpdates: Bool

    init(
        configStore: ConfigStore,
        userDefaults: UserDefaults = .standard
    ) {
        self.configStore = configStore
        self.userDefaults = userDefaults
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        let updater = updaterController.updater
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        canCheckForUpdates = updater.canCheckForUpdates

        bindUpdaterState()
        syncStateFromUpdater()
    }

    func start() {
        guard !didStart else { return }

        migrateLegacyAutomaticChecksPreferenceIfNeeded()
        updaterController.startUpdater()
        didStart = true
        syncStateFromUpdater()
    }

    func checkForUpdates() {
        if !didStart {
            start()
        }

        guard updaterController.updater.canCheckForUpdates else { return }
        updaterController.checkForUpdates(nil)
        syncStateFromUpdater()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = enabled
        syncStateFromUpdater()
    }

    private func bindUpdaterState() {
        automaticChecksObservation = updaterController.updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.syncStateFromUpdater()
            }
        }

        canCheckObservation = updaterController.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.syncStateFromUpdater()
            }
        }
    }

    private func syncStateFromUpdater() {
        let updater = updaterController.updater
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        canCheckForUpdates = updater.canCheckForUpdates
    }

    private func migrateLegacyAutomaticChecksPreferenceIfNeeded() {
        guard !userDefaults.bool(forKey: DefaultsKey.automaticChecksMigrated) else { return }

        if let legacyPreference = configStore.legacyAutomaticUpdateChecksEnabled {
            updaterController.updater.automaticallyChecksForUpdates = legacyPreference
        }

        userDefaults.set(true, forKey: DefaultsKey.automaticChecksMigrated)
    }
}
