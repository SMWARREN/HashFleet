import Foundation
import Observation
import HashFleetCore

@MainActor @Observable
final class MinerTemperatureAlertSettingsModel {
    let deviceID: UUID
    var isEnabled: Bool {
        didSet { savedMessage = nil; error = nil }
    }
    var thresholdText: String {
        didSet { savedMessage = nil; error = nil }
    }
    private(set) var isSaving = false
    private(set) var error: String?
    private(set) var savedMessage: String?
    @ObservationIgnored private let preferences: FleetTemperatureAlertPreferences
    @ObservationIgnored private let requestAuthorization: @MainActor () async -> Bool

    init(
        deviceID: UUID, preferences: FleetTemperatureAlertPreferences,
        requestAuthorization: @escaping @MainActor () async -> Bool = {
            await FleetLocalNotifications.requestAuthorization()
        }
    ) {
        self.deviceID = deviceID
        self.preferences = preferences
        self.requestAuthorization = requestAuthorization
        let policy = preferences.policy(for: deviceID)
        isEnabled = policy.isEnabled
        thresholdText = String(policy.thresholdCelsius)
    }

    var proposedPolicy: MinerTemperatureAlertPolicy? {
        let text = thresholdText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(text) else { return nil }
        return try? MinerTemperatureAlertPolicy(isEnabled: isEnabled, thresholdCelsius: value)
    }

    var hasChanges: Bool { proposedPolicy != preferences.policy(for: deviceID) }

    func save() async {
        guard !isSaving else { return }
        error = nil
        savedMessage = nil
        guard let policy = proposedPolicy else {
            error = MinerTemperatureAlertPolicy.ValidationError.invalidThreshold.localizedDescription
            return
        }
        isSaving = true
        defer { isSaving = false }
        // Request through the existing local notification owner. Other alert flags are untouched.
        if policy.isEnabled, !(await requestAuthorization()) {
#if os(macOS)
            error = "Notification permission was not granted. Your saved settings are unchanged. Allow notifications for Hash Fleet in System Settings, then save again."
#else
            error = "Notification permission was not granted. Your saved settings are unchanged. Allow notifications in Settings, then save again."
#endif
            return
        }
        guard !Task.isCancelled else { return }
        do {
            try preferences.setPolicy(policy, for: deviceID)
            savedMessage = policy.isEnabled ? "Temperature alert settings saved." : "Temperature alerts are off for this miner."
        } catch {
            self.error = "Temperature alert settings could not be saved. Your previous settings are unchanged."
        }
    }
}
