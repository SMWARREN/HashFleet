import Foundation
import Observation
import HashFleetCore

/// Separate, local-only storage for the high-power alarm. Never reads or writes a miner
/// endpoint or other alert choices. Keep one shared instance per FleetStore, using the same
/// defaults suite as that store. Mirrors `FleetTemperatureAlertPreferences`.
@MainActor @Observable
final class FleetPowerAlertPreferences {
    static let keyPrefix = "app.hashfleet.power-alert.v1."

    private struct Record: Codable, Equatable {
        var policy = MinerPowerAlertPolicy()
        var state = MinerPowerAlertState()
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var unreadableDeviceIDs: Set<UUID> = []
    private var policies: [UUID: MinerPowerAlertPolicy] = [:]
    private(set) var persistenceError: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reloadFromDefaults()
    }

    /// Reloads all power alert policies from the underlying UserDefaults suite.
    func reloadFromDefaults() {
        policies.removeAll()
        unreadableDeviceIDs.removeAll()
        persistenceError = nil
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(Self.keyPrefix) {
            guard let id = UUID(uuidString: String(key.dropFirst(Self.keyPrefix.count))) else { continue }
            guard let data = value as? Data, let record = try? JSONDecoder().decode(Record.self, from: data) else {
                // Fail closed for this miner. Preserve unreadable bytes until an explicit user save.
                unreadableDeviceIDs.insert(id)
                persistenceError = "Some power alert settings could not be read. Those alerts are off. Save a miner’s settings to replace its unreadable record."
                continue
            }
            policies[id] = record.policy
        }
    }

    func policy(for deviceID: UUID) -> MinerPowerAlertPolicy {
        // Register local UI observation, but read the shared suite as the source of truth. A
        // separate background FleetStore may have saved settings/state while this store survived.
        _ = policies[deviceID]
        return storedRecord(for: deviceID)?.policy ?? MinerPowerAlertPolicy()
    }

    func setPolicy(_ policy: MinerPowerAlertPolicy, for deviceID: UUID) throws {
        var record = storedRecord(for: deviceID) ?? Record()
        if record.policy != policy { record.state.policyDidChange() }
        record.policy = policy
        try persist(record, for: deviceID)
        policies[deviceID] = policy
        unreadableDeviceIDs.remove(deviceID)
        if unreadableDeviceIDs.isEmpty { persistenceError = nil }
    }

    /// The caller must only pass a newly received power reading, not an old field retained while
    /// merging a partial WebSocket frame. A cached or failed snapshot must never become evidence.
    func observe(
        device: MinerDevice, info: MinerInfo, observedAt: Date?,
        isOnline: Bool, isCached: Bool, now: Date = .now
    ) -> MinerPowerAlertEvent? {
        guard var record = storedRecord(for: device.id), record.policy.isEnabled else { return nil }
        let oldState = record.state
        let event = record.state.observe(MinerPowerAlertObservation(
            deviceID: device.id, minerName: device.name,
            watts: info.raw["power"]?.doubleValue, observedAt: observedAt,
            isOnline: isOnline, isCached: isCached, policy: record.policy, now: now
        ))
        guard record.state != oldState else { return nil }
        do {
            // Persist suppression before releasing the event, including across fresh BG stores.
            try persist(record, for: device.id)
            return event
        } catch {
            persistenceError = "Power alert state could not be saved. No new alert was queued."
            return nil
        }
    }

    func remove(deviceID: UUID) {
        defaults.removeObject(forKey: Self.keyPrefix + deviceID.uuidString)
        policies.removeValue(forKey: deviceID)
        unreadableDeviceIDs.remove(deviceID)
        if unreadableDeviceIDs.isEmpty { persistenceError = nil }
    }

    func removeAll() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.keyPrefix) {
            defaults.removeObject(forKey: key)
        }
        policies.removeAll()
        unreadableDeviceIDs.removeAll()
        persistenceError = nil
    }

    private func persist(_ record: Record, for deviceID: UUID) throws {
        let data = try JSONEncoder().encode(record)
        defaults.set(data, forKey: Self.keyPrefix + deviceID.uuidString)
    }

    private func storedRecord(for deviceID: UUID) -> Record? {
        guard let data = defaults.data(forKey: Self.keyPrefix + deviceID.uuidString) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }
}
