import Foundation
import Observation
import HashFleetCore

/// Demo-mode content, snapshot cache restore, and UserDefaults persistence for FleetStore.
/// Moved to an extension for file and type length; storage keys and behavior are unchanged.
extension FleetStore {
    /// Preference checkpoint key for mid-demo relaunch recovery
    static let preferenceCheckpointKey = "app.hashfleet.demo.preference-checkpoint.v1"
    private static let absentPreferenceKeysCheckpointKey = "__app.hashfleet.demo.absentPreferenceKeys"

    func loadDemo() {
        guard !isDemo else { return }
        cancelRefresh()
        capabilities.reset()
        savedDevices = devices

        // Checkpoint preferences before demo mode
        checkpointPreferences()

        let arguments = ProcessInfo.processInfo.arguments
        devices = arguments.contains("--ui-testing") && arguments.contains("--ui-testing-mixed-fleet")
            ? DemoFleet.mixedDevices : DemoFleet.devices
        let historyMode: DemoFleet.HistoryMode
        if arguments.contains("--ui-testing-history-empty") {
            historyMode = .empty
        } else if arguments.contains("--ui-testing-history-stale-daily") {
            historyMode = .staleDaily
        } else {
            historyMode = .populated
        }
        snapshots = DemoFleet.snapshots(for: devices, historyMode: historyMode)
        isDemo = true
        lastRefresh = Date()
        latestBestShareEvent = nil
        latestBlockFoundEvent = nil
        pendingBestShareEvents = []
        pendingBlockFoundEvents = []
        pendingTemperatureEvents = []
        pendingPowerAlertEvents = []
        pendingStateChangeEvents = []
        pendingMetricAlertEvents = []
    }

    func loadPoolIconDemo() {
        guard !isPoolIconDemo else { return }
        // loadDemo saves real devices only once, including when entered from the standard demo.
        loadDemo()
        devices = DemoFleet.poolIconDevices
        snapshots = DemoFleet.poolIconSnapshots(for: devices)
        isPoolIconDemo = true
        lastRefresh = Date()
    }

    func clearDemo() {
        capabilities.reset()
        guard isDemo else { return }
        cancelRefresh()

        // Restore preferences from checkpoint
        restorePreferencesFromCheckpoint()

        devices = savedDevices
        savedDevices = []
        snapshots = [:]
        lastRefresh = nil
        isDemo = false
        isPoolIconDemo = false
        restoreCachedReadings()
        latestBestShareEvent = nil
        latestBlockFoundEvent = nil
        pendingBestShareEvents = []
        pendingBlockFoundEvents = []
        pendingTemperatureEvents = []
        pendingPowerAlertEvents = []
        pendingStateChangeEvents = []
        pendingMetricAlertEvents = []
    }

    func restoreCachedReadings() {
        guard !isDemo, let data = defaults.data(forKey: Self.snapshotCacheKey), data.count <= 2 * 1024 * 1024,
            let decoded = try? JSONDecoder().decode([String: MinerSnapshotCacheEntry].self, from: data)
        else { return }
        let now = Date()
        var namesChanged = false
        for device in devices.prefix(128) {
            guard let entry = decoded[device.id.uuidString], entry.observedAt <= now.addingTimeInterval(60),
                entry.observedAt.timeIntervalSince1970.isFinite, !entry.fields.isEmpty
            else { continue }
            let restored = entry.restored
            guard let info = restored.info else { continue }
            cachedReadings[device.id.uuidString] = MinerSnapshotCacheEntry(
                info: info,
                observedAt: entry.observedAt
            )
            snapshots[device.id] = restored
            snapshots[device.id]?.isReconnecting = true
            if updateAutomaticName(for: device.id, info: info, persistImmediately: false) {
                namesChanged = true
            }
        }
        if namesChanged { persist() }
    }

    func cacheSuccessfulInfo(_ info: MinerInfo, for id: UUID, at date: Date, force: Bool = false) {
        guard !isDemo, devices.prefix(128).contains(where: { $0.id == id }) else { return }
        let entry = MinerSnapshotCacheEntry(info: info, observedAt: date)
        let previous = cachedReadings[id.uuidString]
        // Settings changes persist immediately. Rapid telemetry-only frames are limited to 5s.
        let telemetry: Set<String> = [
            "hashRate", "hashrate", "power", "temp", "vrTemp", "fanspeed", "fanSpeed", "uptimeSeconds",
            "sharesAccepted", "sharesRejected", "bestDiff", "bestSessionDiff", "blockHeight"
        ]
        let settingsChanged =
            previous?.fields.filter { !telemetry.contains($0.key) }
            != entry.fields.filter { !telemetry.contains($0.key) }
        cachedReadings[id.uuidString] = entry
        guard force || settingsChanged || cachePersistedAt[id].map({ date.timeIntervalSince($0) >= 5 }) != false
        else { return }
        cachePersistedAt[id] = date
        persistCachedReadings()
    }

    func persistCachedReadings() {
        guard !isDemo, let data = try? JSONEncoder().encode(cachedReadings), data.count <= 2 * 1024 * 1024 else {
            return
        }
        defaults.set(data, forKey: Self.snapshotCacheKey)
    }

    func persist() {
        do {
            let encoded = try JSONEncoder().encode(devices)
            if let unreadableStorage {
                let recoveryKey = Self.storageKey + ".recovery." + UUID().uuidString
                defaults.set(unreadableStorage, forKey: recoveryKey)
                guard defaults.data(forKey: recoveryKey) == unreadableStorage else {
                    throw FleetError.recoveryFailed
                }
                self.unreadableStorage = nil
            }
            defaults.set(encoded, forKey: Self.storageKey)
        } catch { persistenceError = "Unable to save your fleet: \(error.localizedDescription)" }
    }

    /// Uses the same defaults domain as this store, including the isolated UI-test domain.
    /// The iOS shared-storage path continues to use FleetMenuBarPreferenceStorage.shared.
    var menuBarPreferenceStorage: FleetMenuBarPreferenceStorage {
#if os(macOS)
        FleetMenuBarPreferenceStorage(defaults: defaults)
#else
        .shared
#endif
    }

    func persistBlockObservations() {
        guard let encoded = try? JSONEncoder().encode(blockObservations) else { return }
        defaults.set(encoded, forKey: Self.blockObservationStorageKey)
    }

    func persistBestShareObservations() {
        guard let encoded = try? JSONEncoder().encode(bestShareObservations) else { return }
        defaults.set(encoded, forKey: Self.bestShareObservationStorageKey)
    }

    func persistStateObservations() {
        guard let encoded = try? JSONEncoder().encode(stateObservations) else { return }
        defaults.set(encoded, forKey: Self.stateObservationStorageKey)
    }

    /// Wipes the telemetry database and every persisted achievement baseline so tracking restarts
    /// fresh, per device, from the next poll. Without clearing the baselines a "Clear all data"
    /// would still compare against the stored firmware `blockFound` counter and could re-surface a
    /// phantom block. The next successful poll re-baselines each device silently (a first
    /// observation never alerts), and genuine future finds are recorded anew in the database.
    @discardableResult
    func clearAllTelemetryAndAchievements(
        clearDatabase: () async throws -> Void = { try await MinerTelemetryDatabase.shared.clearAllDataChecked() }
    ) async -> Bool {
        guard !isDemo else {
            persistenceError = "Demo mode is read only. Stored telemetry was not changed."
            return false
        }
        do {
            try await clearDatabase()
        } catch {
            persistenceError = "Unable to clear telemetry. Achievement baselines were not reset. \(error.localizedDescription)"
            return false
        }
        // A successful retry resolves this operation's error, never an unrelated fleet-save error.
        if persistenceError?.hasPrefix("Unable to clear telemetry.") == true {
            persistenceError = nil
        }

        blockObservations = [:]
        bestShareObservations = [:]
        persistBlockObservations()
        persistBestShareObservations()

        latestBlockFoundEvent = nil
        latestBestShareEvent = nil
        pendingBlockFoundEvents = []
        pendingBestShareEvents = []

        // Drop journaled block/best-share alerts so the dashboard does not rehydrate a stale
        // celebration for data we just deleted. Other alert types are left untouched.
        notificationInbox.removeAll { entry in
            switch entry.event {
            case .blockFound, .bestShare: return true
            default: return false
            }
        }
        persistNotificationInbox()
        return true
    }

    // MARK: - Durable notification journal

    private static let notificationInboxLimit = 100
    private static let notificationInboxRetention: TimeInterval = 14 * 24 * 60 * 60

    /// Restores alerts produced by a background store. The journal intentionally outlives system
    /// notification delivery so the dashboard can present the same event after the app opens.
    func restoreNotificationInbox() {
        guard let data = defaults.data(forKey: Self.notificationInboxStorageKey),
              let entries = try? JSONDecoder().decode([FleetNotificationInboxEntry].self, from: data)
        else { return }

        let cutoff = Date().addingTimeInterval(-Self.notificationInboxRetention)
        let deviceIDs = Set(devices.map(\.id))
        let retained = entries
            .filter { $0.event.occurredAt >= cutoff && deviceIDs.contains($0.event.deviceID) }
            .sorted { $0.event.occurredAt < $1.event.occurredAt }
        let trimmed = Array(retained.suffix(Self.notificationInboxLimit))
        let changed = trimmed != entries
        notificationInbox = trimmed
        hydrateLatestInAppEvents()
        if changed { persistNotificationInbox() }
    }

    /// Adds an event once. Dedupe is based on the miner observation as well as the UUID so two
    /// FleetStore instances polling at the same time cannot create two alerts for one change.
    func enqueueNotification(_ event: FleetNotificationEvent) {
        guard !isDemo else { return }
        guard !isDuplicateNotification(event) else { return }
        notificationInbox.append(FleetNotificationInboxEntry(
            event: event, systemDelivered: false, inAppDelivered: false))
        trimNotificationInbox()
        persistNotificationInbox()
        pendingNotificationsChangedAt = Date()
    }

    /// A connectivity change is a duplicate only when it repeats the miner's latest recorded
    /// transition (two stores both seeing the same outage). A time bucket is not enough: a miner
    /// that drops, recovers and drops again within minutes must announce the second outage, or
    /// the shared per-miner notification would keep saying "back online" while it is down.
    private func isDuplicateNotification(_ event: FleetNotificationEvent) -> Bool {
        if notificationInbox.contains(where: { $0.id == event.id }) { return true }
        if case .stateChange = event { return matchingLatestTransitionIndex(for: event) != nil }
        return notificationInbox.contains { $0.dedupeKey == event.dedupeKey }
    }

    /// The miner's most recent connectivity entry, when it records the same transition as `event`.
    private func matchingLatestTransitionIndex(for event: FleetNotificationEvent) -> Int? {
        guard case .stateChange(let change) = event else { return nil }
        guard let index = notificationInbox.lastIndex(where: { entry in
            if case .stateChange(let other) = entry.event { return other.deviceID == change.deviceID }
            return false
        }), case .stateChange(let previous) = notificationInbox[index].event,
            previous.kind == change.kind
        else { return nil }
        return index
    }

    @discardableResult
    func ensureNotificationEntry(for event: FleetNotificationEvent) -> FleetNotificationInboxEntry {
        if let index = notificationEntryIndex(for: event) {
            return notificationInbox[index]
        }
        enqueueNotification(event)
        return notificationEntryIndex(for: event).map { notificationInbox[$0] }
            ?? FleetNotificationInboxEntry(event: event, systemDelivered: false, inAppDelivered: false)
    }

    /// Exact event first. A connectivity change then resolves to the miner's latest transition
    /// only when it is the same transition (the one it was collapsed into), never to an older
    /// outage in the same time window.
    private func notificationEntryIndex(for event: FleetNotificationEvent) -> Int? {
        if let index = notificationInbox.firstIndex(where: { $0.id == event.id }) { return index }
        if case .stateChange = event { return matchingLatestTransitionIndex(for: event) }
        return notificationInbox.firstIndex { $0.dedupeKey == event.dedupeKey }
    }

    /// Returns true only for a journal entry that has not already been handed to
    /// UNUserNotificationCenter. The caller posts, then marks it delivered.
    func shouldPostSystemNotification(for event: FleetNotificationEvent) -> Bool {
        !ensureNotificationEntry(for: event).systemDelivered
    }

    /// Marks a notification as delivered or intentionally suppressed because its preference was
    /// off. Keeping the record prevents an old event from resurfacing after the user re-enables it.
    func markSystemNotificationDelivered(for event: FleetNotificationEvent) {
        updateNotificationEntry(for: event) { $0.systemDelivered = true }
    }

    /// Marks the in-app presentation independently from system delivery. This is what makes the
    /// HashWatcher-style behavior possible: one event can be in Notification Center and on the
    /// dashboard without being treated as two detections.
    func markInAppNotificationDelivered(for event: FleetNotificationEvent) {
        updateNotificationEntry(for: event) {
            $0.inAppDelivered = true
            $0.inAppAcceptancePending = nil
        }
    }

    /// Written before handing an event to durable presentation storage. A failed handoff remains
    /// retryable even after system delivery is suppressed for the foreground scene.
    func markInAppNotificationAcceptancePending(for event: FleetNotificationEvent) {
        _ = ensureNotificationEntry(for: event)
        updateNotificationEntry(for: event) { $0.inAppAcceptancePending = true }
    }

    /// True when this event (or an earlier detection of the same observation) has already been
    /// shown in the app, so re-detection or a view reappearing never presents it twice.
    func isInAppNotificationDelivered(_ event: FleetNotificationEvent) -> Bool {
        notificationInbox.contains {
            ($0.id == event.id || $0.dedupeKey == event.dedupeKey) && $0.inAppDelivered
        }
    }

    /// Reloads detection baselines that a BGTask handler's separate FleetStore may have written
    /// while this scene was suspended. Without this the foreground store compares against its
    /// stale in-memory state and re-announces an outage or milestone that was already delivered.
    func reloadSharedDetectionBaselines() {
        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: Self.stateObservationStorageKey),
            let observations = try? decoder.decode([String: MinerFleetStateObservation].self, from: data) {
            stateObservations = observations
        }
        if let data = defaults.data(forKey: Self.bestShareObservationStorageKey),
            let observations = try? decoder.decode([String: MinerBestShareObservation].self, from: data) {
            bestShareObservations = observations
        }
        if let data = defaults.data(forKey: Self.blockObservationStorageKey),
            let observations = try? decoder.decode([String: MinerBlockFoundObservation].self, from: data) {
            blockObservations = observations
        }
    }

    var undeliveredSystemNotificationEntries: [FleetNotificationInboxEntry] {
        notificationInbox.filter { !$0.systemDelivered }
    }

    private func updateNotificationEntry(
        for event: FleetNotificationEvent,
        _ update: (inout FleetNotificationInboxEntry) -> Void
    ) {
        guard let index = notificationEntryIndex(for: event) else { return }
        update(&notificationInbox[index])
        persistNotificationInbox()
    }

    private func trimNotificationInbox() {
        let cutoff = Date().addingTimeInterval(-Self.notificationInboxRetention)
        notificationInbox = notificationInbox
            .filter { $0.event.occurredAt >= cutoff }
            .sorted { $0.event.occurredAt < $1.event.occurredAt }
        if notificationInbox.count > Self.notificationInboxLimit {
            notificationInbox = Array(notificationInbox.suffix(Self.notificationInboxLimit))
        }
    }

    func persistNotificationInbox() {
        guard let encoded = try? notificationInboxEncoder.encode(notificationInbox), encoded.count <= 512 * 1024 else {
            return
        }
        defaults.set(encoded, forKey: Self.notificationInboxStorageKey)
    }

    private func hydrateLatestInAppEvents() {
        let candidates = notificationInbox.filter { !$0.inAppDelivered }
        let latestBest = candidates
            .compactMap { entry -> (FleetNotificationInboxEntry, MinerBestShareEvent)? in
                guard case .bestShare(let event) = entry.event else { return nil }
                return (entry, event)
            }
            .max { $0.1.occurredAt < $1.1.occurredAt }
        let latestBlock = candidates
            .compactMap { entry -> (FleetNotificationInboxEntry, MinerBlockFoundEvent)? in
                guard case .blockFound(let event) = entry.event else { return nil }
                return (entry, event)
            }
            .max { $0.1.occurredAt < $1.1.occurredAt }

        latestBestShareEvent = latestBest?.1
        latestBlockFoundEvent = latestBlock?.1

        // These latest-value fields are summaries only. Restoring them must not claim older
        // records as shown: delivery hands every undelivered milestone to the popup queue.
    }

    // MARK: - Preference Checkpoint

    /// Static method to restore preferences from checkpoint during init (before self is available)
    static func restorePreferencesFromCheckpointIfNeeded(defaults: UserDefaults) {
        guard let data = defaults.data(forKey: Self.preferenceCheckpointKey),
              let checkpoint = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
                ?? (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            // No checkpoint exists, nothing to restore
            return
        }

        // Match clearDemo: remove per-device alert overrides created only while demo was active.
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix(FleetTemperatureAlertPreferences.keyPrefix)
                || key.hasPrefix(FleetPowerAlertPreferences.keyPrefix) {
            if checkpoint[key] == nil {
                defaults.removeObject(forKey: key)
            }
        }

        // Restore key absence as well as stored values so demo mutations never create previously
        // absent defaults. This also keeps default-vs-explicit values behavior intact.
        if let absentKeys = checkpoint[Self.absentPreferenceKeysCheckpointKey] as? [String] {
            for key in absentKeys { defaults.removeObject(forKey: key) }
        }
        for (key, value) in checkpoint {
            guard key != Self.absentPreferenceKeysCheckpointKey else { continue }
            defaults.set(value, forKey: key)
        }

        // Clear checkpoint after restoration
        defaults.removeObject(forKey: Self.preferenceCheckpointKey)
    }

    /// Captures all current preference values into a checkpoint for mid-demo relaunch recovery
    private func checkpointPreferences() {
        var checkpoint: [String: Any] = [:]

        // Capture all preference keys from FleetPreferences.Keys
        let prefKeys = [
            FleetPreferences.Keys.appearance,
            FleetPreferences.Keys.sort,
            FleetPreferences.Keys.ascending,
            FleetPreferences.Keys.compactCards,
            FleetPreferences.Keys.externalData,
            FleetPreferences.Keys.realtimeMonitoring,
            FleetPreferences.Keys.blockNotificationsEnabled,
            FleetPreferences.Keys.bestShareNotificationsEnabled,
            FleetPreferences.Keys.sessionBestNotificationsEnabled,
            FleetPreferences.Keys.stateChangeNotificationsEnabled,
            FleetPreferences.Keys.metricAlertNotificationsEnabled,
            FleetPreferences.Keys.powerAlertNotificationsEnabled,
            FleetPreferences.Keys.tourSeen,
            FleetPreferences.Keys.tourSuppressed,
            FleetPreferences.Keys.dashboardCoins,
            FleetPreferences.Keys.systemAppearanceMigration,
            FleetPreferences.Keys.telemetryRetention,
            FleetPreferences.Keys.telemetryStorageEnabled,
            FleetMenuBarPreferenceStorage.key,
            FleetMenuBarPreferenceStorage.contentKey
        ]

        for key in prefKeys {
            if let value = defaults.object(forKey: key) {
                checkpoint[key] = value
            }
        }
        checkpoint[Self.absentPreferenceKeysCheckpointKey] = prefKeys.filter {
            defaults.object(forKey: $0) == nil
        }

        // Also checkpoint temperature and power alert preferences (keyed by prefix pattern)
        for (key, value) in defaults.dictionaryRepresentation()
            where key.hasPrefix(FleetTemperatureAlertPreferences.keyPrefix)
                || key.hasPrefix(FleetPowerAlertPreferences.keyPrefix) {
            checkpoint[key] = value
        }

        if let data = try? PropertyListSerialization.data(fromPropertyList: checkpoint, format: .binary, options: 0) {
            defaults.set(data, forKey: Self.preferenceCheckpointKey)
        }
    }

    /// Restores preferences from checkpoint and clears the checkpoint
    func restorePreferencesFromCheckpoint() {
        guard let data = defaults.data(forKey: Self.preferenceCheckpointKey),
              let checkpoint = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
                ?? (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            // No checkpoint exists, nothing to restore
            return
        }

        // Clean up any demo alert keys that were added during demo
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix(FleetTemperatureAlertPreferences.keyPrefix)
                || key.hasPrefix(FleetPowerAlertPreferences.keyPrefix) {
            if checkpoint[key] == nil {
                defaults.removeObject(forKey: key)
            }
        }

        // Restore key absence as well as stored values so demo mutations never create previously
        // absent defaults. This also keeps default-vs-explicit values behavior intact.
        if let absentKeys = checkpoint[Self.absentPreferenceKeysCheckpointKey] as? [String] {
            for key in absentKeys { defaults.removeObject(forKey: key) }
        }
        for (key, value) in checkpoint {
            guard key != Self.absentPreferenceKeysCheckpointKey else { continue }
            defaults.set(value, forKey: key)
        }

        // Clear checkpoint after restoration
        defaults.removeObject(forKey: Self.preferenceCheckpointKey)

        // Reload in-memory preference instances so live references reflect restored defaults
        preferences.reloadFromDefaults()
        temperatureAlerts.reloadFromDefaults()
        powerAlerts.reloadFromDefaults()
    }
}
