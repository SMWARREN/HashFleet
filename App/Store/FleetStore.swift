import Foundation
import Observation
import HashFleetCore

@MainActor @Observable
final class FleetStore {
    let preferences: FleetPreferences
    let temperatureAlerts: FleetTemperatureAlertPreferences
    let powerAlerts: FleetPowerAlertPreferences
    let capabilities: MinerCapabilitiesStore
    let firmwareUpdates: FirmwareUpdateStore
    var devices: [MinerDevice] = []
    /// Whole-fleet view. Reading this observes every miner, so a view that shows one miner should
    /// use `snapshot(for:)` instead; otherwise each live frame from any miner re-renders it.
    var snapshots: [UUID: MinerSnapshot] = [:] {
        didSet { syncSnapshotCells() }
    }
    /// Per-miner observation cells, created lazily for miners that some view actually reads.
    @ObservationIgnored private var snapshotCells: [UUID: MinerSnapshotCell] = [:]
    var isDemo = false {
        didSet { hardwareControlGate?.update(isDemo: isDemo) }
    }
    var isPoolIconDemo = false
    var isRefreshing = false
    var lastRefresh: Date?
    /// Miner IDs whose primary dashboard feed is currently a live WebSocket.
    var liveConnectedDeviceIDs: Set<UUID> = []
    /// Miner IDs confirmed to expose `/api/system/scoreboard` (its authoritative, NVS-persisted
    /// best-share record). `detectBestShare` skips writing its own achievement row for these
    /// devices so the same real share isn't logged twice (once from polling, once from the
    /// scoreboard import). Devices not yet confirmed, or confirmed to lack the endpoint, still get
    /// the polling-based write so older firmware without this endpoint keeps a permanent record.
    var scoreboardSupportedDeviceIDs: Set<UUID> = []
    /// Connection failures are informational. The last complete snapshot remains visible while the
    /// store falls back to HTTP and retries the live feed.
    var liveConnectionErrors: [UUID: String] = [:]
    /// The latest in-app milestone. It is hydrated from the durable notification journal on a
    /// cold launch and never sent to widgets. This drives the on-screen celebration, which can
    /// show one event of each milestone type at a time.
    var latestBestShareEvent: MinerBestShareEvent?
    /// The latest explicit block-found event. Difficulty shares never populate this value.
    var latestBlockFoundEvent: MinerBlockFoundEvent?
    /// Every event detected since they were last drained, in detection order.
    ///
    /// A refresh covers the whole fleet, so two miners can each report a milestone in one pass.
    /// The `latest*` properties only keep the final one, which is correct for a single on-screen
    /// celebration but would silently drop notifications for every other miner. Notification
    /// delivery drains these instead so each miner's event is actually delivered.
    var pendingBestShareEvents: [MinerBestShareEvent] = []
    var pendingBlockFoundEvents: [MinerBlockFoundEvent] = []
    var pendingTemperatureEvents: [MinerTemperatureAlertEvent] = []
    var pendingPowerAlertEvents: [MinerPowerAlertEvent] = []
    var pendingStateChangeEvents: [MinerStateChangeEvent] = []
    var pendingMetricAlertEvents: [MinerMetricAlertEvent] = []
    /// Bumped whenever a notification event is queued. The app delivers on this signal, not on
    /// `lastRefresh`, because a live-socket outage records a failure without any fresh reading.
    var pendingNotificationsChangedAt: Date?
    /// A bounded, durable journal of alerts detected by either foreground or background polling.
    /// System delivery and in-app presentation are tracked independently so opening the app can
    /// show the same event without scheduling a second system notification.
    var notificationInbox: [FleetNotificationInboxEntry] = []
    var persistenceError: String?

    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored private let hardwareControlGate: FleetHardwareControlGate?
    @ObservationIgnored let session: URLSession
    @ObservationIgnored let achievementMerger: @MainActor (UUID, UUID) async throws -> Void
    @ObservationIgnored let achievementDeletion: @MainActor (UUID) async -> Void
    @ObservationIgnored var achievementAliases: [UUID: UUID] = [:]
    @ObservationIgnored var achievementMergeProtectedIDs: Set<UUID> = []
    @ObservationIgnored var isDeduplicatingDevices = false
    var savedDevices: [MinerDevice] = []
    var generation = UUID()
    var refreshTask: Task<Void, Never>?
    var liveGeneration = UUID()
    var liveTasks: [UUID: Task<Void, Never>] = [:]
    var unreadableStorage: Data?
    var blockObservations: [String: MinerBlockFoundObservation] = [:]
    /// Persisted connectivity/metric baselines so offline transitions and significant metric
    /// changes are also detected from a background refresh or a cold launch.
    var stateObservations: [String: MinerFleetStateObservation] = [:]
    /// Persisted best-share baselines. Without these a background refresh always starts from a
    /// nil previous reading, so a new best share could never be detected outside a live session.
    var bestShareObservations: [String: MinerBestShareObservation] = [:]
    var cachedReadings: [String: MinerSnapshotCacheEntry] = [:]
    var cachePersistedAt: [UUID: Date] = [:]
    /// Mac only: partial live frames waiting for the next fleet-wide publish. Every miner's
    /// frames are applied together in one main-actor turn, so the UI renders once per interval
    /// for the whole fleet instead of once per miner at unaligned moments.
    @ObservationIgnored var pendingLiveUpdates: [UUID: PendingLiveUpdate] = [:]
    @ObservationIgnored var liveAppliedDeviceIDs: Set<UUID> = []
    @ObservationIgnored var liveFlushTask: Task<Void, Never>?
    static let snapshotCacheKey = "app.hashfleet.last-known-settings.v1"
    static let storageKey = "app.hashfleet.devices.v1"
    static let blockObservationStorageKey = "app.hashfleet.block-observations.v1"
    static let bestShareObservationStorageKey = "app.hashfleet.best-share-observations.v1"
    static let stateObservationStorageKey = "app.hashfleet.state-observations.v1"
    static let notificationInboxStorageKey = "app.hashfleet.notification-inbox.v1"

    init(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        hardwareControlGate: FleetHardwareControlGate? = nil,
        achievementMerger: @escaping @MainActor (UUID, UUID) async throws -> Void = { source, target in
            _ = try await MinerTelemetryDatabase.shared.mergeAchievementsChecked(
                fromMinerId: source.uuidString, intoMinerId: target.uuidString
            )
        },
        achievementDeletion: @escaping @MainActor (UUID) async -> Void = { id in
            await MinerTelemetryDatabase.shared.deleteAchievements(minerId: id.uuidString)
        }
    ) {
        self.defaults = defaults
        self.hardwareControlGate = hardwareControlGate
        self.session = session
        self.achievementMerger = achievementMerger
        self.achievementDeletion = achievementDeletion

        // If a checkpoint exists from a mid-demo relaunch, restore it before creating preferences
        Self.restorePreferencesFromCheckpointIfNeeded(defaults: defaults)

        preferences = FleetPreferences(defaults: defaults)
        temperatureAlerts = FleetTemperatureAlertPreferences(defaults: defaults)
        powerAlerts = FleetPowerAlertPreferences(defaults: defaults)
        capabilities = MinerCapabilitiesStore(session: session)
        firmwareUpdates = FirmwareUpdateStore(defaults: defaults, session: session)
        if let data = defaults.data(forKey: Self.storageKey) {
            do {
                devices = try JSONDecoder().decode([MinerDevice].self, from: data)
            } catch {
                unreadableStorage = data
                persistenceError =
                    "Your saved fleet could not be read. The original data has not been overwritten. " +
                        "\(error.localizedDescription)"
            }
        }
        if let data = defaults.data(forKey: Self.blockObservationStorageKey),
            let observations = try? JSONDecoder().decode([String: MinerBlockFoundObservation].self, from: data) {
            blockObservations = observations
        }
        if let data = defaults.data(forKey: Self.bestShareObservationStorageKey),
            let observations = try? JSONDecoder().decode([String: MinerBestShareObservation].self, from: data) {
            bestShareObservations = observations
        }
        if let data = defaults.data(forKey: Self.stateObservationStorageKey),
            let observations = try? JSONDecoder().decode([String: MinerFleetStateObservation].self, from: data) {
            stateObservations = observations
        }
        let isLaunchDemo =
            ProcessInfo.processInfo.arguments.contains("--demo")
            || ProcessInfo.processInfo.arguments.contains("--pool-icon-demo")
        if !isLaunchDemo {
            restoreCachedReadings()
            restoreNotificationInbox()
        }
        if ProcessInfo.processInfo.arguments.contains("--pool-icon-demo") {
            loadPoolIconDemo()
        } else if ProcessInfo.processInfo.arguments.contains("--demo") {
            loadDemo()
        }
        hardwareControlGate?.update(isDemo: isDemo)
    }

    /// UI projection only. Hidden release features must never delete persisted fleet entries.
    var visibleDevices: [MinerDevice] { FleetReleaseFeatures.visibleDevices(devices) }

    var onlineCount: Int { activeSnapshots.count }

    var reconnectingDeviceIDs: Set<UUID> {
        Set(visibleDevices.filter { snapshots[$0.id]?.isReconnecting == true }.map(\.id))
    }

    var reconnectingCount: Int { reconnectingDeviceIDs.count }

    var isReconnecting: Bool { reconnectingCount > 0 }

    /// Mark the pending check synchronously, before the scene's asynchronous monitoring starts.
    func beginReconnecting() {
        guard !isDemo else { return }
        for device in visibleDevices {
            var snapshot = snapshots[device.id] ?? MinerSnapshot()
            if !snapshot.isReconnecting {
                snapshot.isReconnecting = true
                snapshots[device.id] = snapshot
            }
        }
    }

    /// Totals are computed from raw reported fields only. A miner that answered without a usable
    /// metric contributes nothing rather than a fabricated zero, and the reading carries how many
    /// online miners actually reported so callers can say so instead of implying a whole-fleet total.
    var hashrateReading: FleetMetricTotal { totals.hashrate }
    var powerReading: FleetMetricTotal { totals.power }
    /// Only miners that reported both hashrate and power. Mixing an unpaired subtotal of one with a
    /// different subtotal of the other would produce a meaningless efficiency figure.
    var efficiencyReading: FleetEfficiencyTotal { totals.efficiency }

    /// A shared widget payload is deliberately all-or-nothing. Do not replace a useful cached
    /// snapshot with `.empty` while one online miner is missing a metric, but do allow an actually
    /// empty fleet or a completed all-offline refresh to publish honestly.
    var canPublishGlance: Bool {
        visibleDevices.isEmpty || (lastRefresh != nil && totals.isPublishable)
    }

    /// Per-miner Mac rows remain useful even if an online miner omits power or hashrate.
    var canPublishMenuBar: Bool { visibleDevices.isEmpty || lastRefresh != nil }

    var menuBarSnapshot: FleetMenuBarSnapshot {
        var result = FleetGlanceCoordinator.menuBarSnapshot(
            devices: visibleDevices, snapshots: snapshots,
            updatedAt: lastRefresh ?? .distantPast, isDemo: isDemo
        )
        result.notifications = FleetActivityPresentation.notifications(from: self)
        return result
    }

    /// Sum of usable reported hashrate in GH/s. Excludes online miners that did not report one.
    var totalHashrate: Double { totals.hashrate.value }
    /// Sum of usable reported power in watts. Excludes online miners that did not report one.
    var totalPower: Double { totals.power.value }

    private var totals: FleetTotals { FleetTotals(snapshots: activeSnapshots) }

    var glance: FleetGlance {
        let value = FleetGlance(
            updatedAt: lastRefresh ?? .distantPast,
            onlineCount: onlineCount,
            minerCount: visibleDevices.count,
            hashrateGHs: totalHashrate,
            powerWatts: totalPower,
            isDemo: isDemo
        )
        // The shared payload has no room for completeness, and widgets would present a partial
        // subtotal as the whole fleet. Publish nothing rather than something quietly wrong.
        guard totals.isPublishable else { return .empty }
        return value.isValid ? value : .empty
    }

    private var activeSnapshots: [MinerSnapshot] {
        visibleDevices.compactMap { snapshots[$0.id] }.filter {
            $0.info != nil && $0.error == nil && !$0.isCached && !$0.isReconnecting
        }
    }

    func updateAutomaticName(for id: UUID, info: MinerInfo) {
        guard !isDemo, let index = devices.firstIndex(where: { $0.id == id }) else { return }
        let device = devices[index]
        let host = (try? device.validatedURL())?.host ?? ""
        let legacyDefault =
            device.name.isEmpty || device.name.caseInsensitiveCompare(host) == .orderedSame
            || ["bitaxe", "bitax"].contains(device.name.lowercased())
        guard device.usesAutomaticName ?? legacyDefault else { return }
        let name = MinerDisplayName.automatic(info: info, address: device.address)
        guard device.name != name || device.usesAutomaticName != true else { return }
        devices[index].name = name
        devices[index].usesAutomaticName = true
        persist()
    }

    func remove(_ device: MinerDevice, deleteAchievementHistory: Bool = true) {
        // The database may already have committed while its MainActor continuation is waiting.
        // Purging either identity now could destroy the other miner entry's transferred events.
        guard !deleteAchievementHistory || !achievementMergeProtectedIDs.contains(device.id) else {
            persistenceError = "This miner is finishing an achievement-history merge. Try removing it again when the refresh finishes. Nothing was removed."
            return
        }
        if !isDemo { MinerCredentialStore.remove(reference: device.keychainCredentialReference) }
        if !isDemo { temperatureAlerts.remove(deviceID: device.id) }
        if !isDemo { powerAlerts.remove(deviceID: device.id) }
        liveTasks.removeValue(forKey: device.id)?.cancel()
        liveConnectedDeviceIDs.remove(device.id)
        liveConnectionErrors.removeValue(forKey: device.id)
        capabilities.remove(device.id)
        devices.removeAll { $0.id == device.id }
        snapshots.removeValue(forKey: device.id)
        blockObservations.removeValue(forKey: device.id.uuidString)
        persistBlockObservations()
        stateObservations.removeValue(forKey: device.id.uuidString)
        persistStateObservations()
        bestShareObservations.removeValue(forKey: device.id.uuidString)
        persistBestShareObservations()
        if !isDemo {
            cachedReadings.removeValue(forKey: device.id.uuidString)
            cachePersistedAt.removeValue(forKey: device.id)
            persistCachedReadings()
            persist()
            // Explicit removal keeps its existing deletion semantics. Automatic dedup has
            // already transferred history and must not launch a later destructive purge.
            if deleteAchievementHistory {
                Task { @MainActor in await achievementDeletion(device.id) }
            }
            // A removed miner's offline/temperature/power alerts would otherwise linger in
            // Notification Center and could never be replaced by a recovery.
            notificationInbox.removeAll { $0.event.deviceID == device.id }
            persistNotificationInbox()
            FleetLocalNotifications.removeStatusNotifications(for: device.id)
            FleetInAppAlertCenter.shared.removeAll(for: device.id)
        }
    }

    /// Removes every saved miner using the same per-miner cleanup as a single removal.
    func removeAllMiners() {
        for device in devices { remove(device) }
    }

    func refresh() async {
        guard !isDemo, !Task.isCancelled else { return }
        if isRefreshing {
            // A manual refresh joins already-owned reads instead of ending its spinner early.
            await refreshTask?.value
            return
        }
        let token = UUID()
        generation = token
        isRefreshing = true
        let work = Task { [weak self] in
            guard let self else { return }
            await self.performRefresh(token: token)
        }
        refreshTask = work
        await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
        if token == generation {
            refreshTask = nil
            isRefreshing = false
            // Snapshots now carry each miner's MAC, so collapse any duplicate that was added
            // under a second address (IP vs mDNS hostname) for the same physical miner.
            await deduplicateDevicesByMAC()
        }
    }

    /// A write must not join a read started before it. Invalidate that read's generation before
    /// starting a new one. Live monitoring ownership is deliberately left intact.
    /// Returning false prevents a settings form from reloading cached or wrong-target values.
    func refreshAfterWrite(for device: MinerDevice) async -> Bool {
        guard !Task.isCancelled, !isDemo,
              visibleDevices.contains(where: { $0.id == device.id && $0.address == device.address && $0.kind == device.kind })
        else { return false }
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
        let startedAt = Date()
        await refresh()
        guard !Task.isCancelled, !isDemo,
              visibleDevices.contains(where: { $0.id == device.id && $0.address == device.address && $0.kind == device.kind }),
              let snapshot = snapshots[device.id],
              let observedAt = snapshot.completeSnapshotAt, observedAt >= startedAt
        else { return false }
        return MinerWriteAvailability.allows(snapshot)
    }

    /// Returns and clears every milestone detected since the last drain, so a refresh covering
    /// several miners delivers one notification per miner rather than only the last one.
    func drainPendingNotificationEvents() -> (
        bestShares: [MinerBestShareEvent], blocksFound: [MinerBlockFoundEvent],
        temperatures: [MinerTemperatureAlertEvent], powerAlerts: [MinerPowerAlertEvent],
        stateChanges: [MinerStateChangeEvent], metricAlerts: [MinerMetricAlertEvent]
    ) {
        defer {
            pendingBestShareEvents = []
            pendingBlockFoundEvents = []
            pendingTemperatureEvents = []
            pendingPowerAlertEvents = []
            pendingStateChangeEvents = []
            pendingMetricAlertEvents = []
        }
        return (pendingBestShareEvents, pendingBlockFoundEvents, pendingTemperatureEvents,
            pendingPowerAlertEvents, pendingStateChangeEvents, pendingMetricAlertEvents)
    }

    /// Cancels both scene-driven and pull-to-refresh network work.
    /// Generation changes also reject results already racing with cancellation.
    func cancelRefresh() {
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        cancelLiveMonitoring()
        capabilities.cancelAll()
        isRefreshing = false
    }

    private func performRefresh(token: UUID) async {
        let targets = visibleDevices
        let session = session
        // Cap concurrent requests so a large fleet does not overwhelm a home router.
        for offset in stride(from: 0, to: targets.count, by: 4) {
            guard !Task.isCancelled, token == generation else { return }
            let batch = Array(targets[offset..<min(offset + 4, targets.count)])
            await poll(batch, token: token, session: session)
        }
        if !Task.isCancelled, token == generation { lastRefresh = Date() }
    }

    private func poll(_ batch: [MinerDevice], token: UUID, session: URLSession) async {
        // Network work and JSON decoding run in a nonisolated helper. Only the completed batch
        // crosses back to FleetStore's main actor, so a slow response cannot repeatedly invalidate
        // the visible dashboard while the other miners are still being fetched.
        let results = await FleetTelemetryBatchFetcher.fetch(batch, session: session)
        guard !Task.isCancelled, token == generation else { return }
        for result in results {
            guard let target = batch.first(where: { $0.id == result.id }),
                  visibleDevices.contains(where: {
                      $0.id == target.id && $0.address == target.address && $0.kind == target.kind
                  }) else { continue }
            apply(result, token: token)
        }
    }

    private func apply(_ result: PollResult, token: UUID) {
        guard !Task.isCancelled, token == generation, visibleDevices.contains(where: { $0.id == result.id })
        else { return }
        guard let info = result.info else {
            recordFailedInfo(result.error ?? "Miner did not return a reading.", for: result.id)
            return
        }
        let updatedAt = Date()
        let previous = snapshots[result.id]?.info
        let didPublish = recordSuccessfulInfo(info, for: result.id, at: updatedAt)
        guard didPublish else { return }
        let identityKeys = ["ASICModel", "asicModel", "boardVersion", "version", "axeOSVersion"]
        if let previous, identityKeys.contains(where: { previous.raw[$0] != info.raw[$0] }) {
            capabilities.remove(result.id)
        }
        guard let device = devices.first(where: { $0.id == result.id }), device.kind == .espMiner else { return }
        Task { [weak self] in
            guard let self, !Task.isCancelled, token == self.generation, !self.isDemo,
                self.visibleDevices.contains(where: { $0.id == device.id })
            else { return }
            await self.capabilities.autoDetect(device: device, observedInfo: info, isDemo: self.isDemo)
        }
    }

    /// Local fixture mutation only. Refuses real miners, other demo modes and invalid slots.
    func previewPool(slot: Int, for deviceID: UUID) {
        guard isDemo, isPoolIconDemo, SoloPoolPreset.allCases.indices.contains(slot),
            devices.contains(where: { $0.id == deviceID }),
            var snapshot = snapshots[deviceID], var raw = snapshot.info?.raw
        else { return }
        raw["activePoolIndex"] = .integer(Int64(slot))
        snapshot.info = MinerInfo(raw: raw)
        snapshot.updatedAt = Date()
        snapshots[deviceID] = snapshot
        lastRefresh = snapshot.updatedAt
    }

    /// Returns the observation cell for one miner, creating it on first read. Reads the macro's
    /// backing storage (`_snapshots`) directly so a caller rendering one miner never registers a
    /// dependency on the whole `snapshots` dictionary.
    fileprivate func snapshotCell(for deviceID: UUID) -> MinerSnapshotCell {
        if let cell = snapshotCells[deviceID] { return cell }
        let cell = MinerSnapshotCell(_snapshots[deviceID])
        snapshotCells[deviceID] = cell
        return cell
    }

    /// Pushes changed values into the cells that exist. Equal values are skipped so a miner whose
    /// snapshot did not change does not notify its readers. Cells for removed miners are dropped.
    private func syncSnapshotCells() {
        guard !snapshotCells.isEmpty else { return }
        for (id, cell) in snapshotCells {
            let current = _snapshots[id]
            if current == nil, !devices.contains(where: { $0.id == id }) {
                cell.value = nil
                snapshotCells.removeValue(forKey: id)
            } else if cell.value != current {
                cell.value = current
            }
        }
    }

}

/// Fetches one bounded batch away from FleetStore's main actor. URLSession itself is asynchronous,
/// but keeping request construction and JSON decoding in this nonisolated type prevents a large
/// fleet refresh from inheriting the UI actor for the synchronous portions of each request.
private enum FleetTelemetryBatchFetcher {
    static func fetch(_ devices: [MinerDevice], session: URLSession) async -> [PollResult] {
        let indexedResults = await withTaskGroup(of: (Int, PollResult).self, returning: [(Int, PollResult)].self) { group in
            for (index, device) in devices.enumerated() {
                group.addTask(priority: .utility) {
                    do {
                        let info: MinerInfo
                        switch device.kind {
                        case .espMiner:
                            info = try await MinerAPIClient(device: device, session: session).info()
                        case .xmrig:
                            let token = MinerCredentialStore.token(for: device.keychainCredentialReference)
                            info = try await XMRigAPIClient(
                                device: device,
                                bearerToken: token,
                                session: session
                            ).summary()
                        }
                        return (index, PollResult(id: device.id, info: info, error: nil))
                    } catch {
                        return (index, PollResult(id: device.id, info: nil, error: error.localizedDescription))
                    }
                }
            }

            var results: [(Int, PollResult)] = []
            results.reserveCapacity(devices.count)
            for await result in group {
                results.append(result)
            }
            return results
        }

        // Keep notification and snapshot application deterministic even though requests finish in
        // arbitrary order. The outer refresh still limits this helper to four devices at a time.
        return indexedResults.sorted { $0.0 < $1.0 }.map(\.1)
    }
}

// MARK: - Per-miner snapshot observation

/// One miner's snapshot, observed independently of the rest of the fleet.
@MainActor @Observable
final class MinerSnapshotCell {
    var value: MinerSnapshot?
    init(_ value: MinerSnapshot?) { self.value = value }
}

extension FleetStore {
    /// One miner's latest snapshot. Observes only that miner: updates to other miners, which
    /// arrive continuously from live WebSocket frames, no longer re-render the caller.
    func snapshot(for deviceID: UUID) -> MinerSnapshot? {
        snapshotCell(for: deviceID).value
    }

    /// `snapshots` restricted to the given miners, observing only those miners.
    func snapshots(for deviceIDs: [UUID]) -> [UUID: MinerSnapshot] {
        var result: [UUID: MinerSnapshot] = [:]
        for id in deviceIDs {
            if let snapshot = snapshot(for: id) { result[id] = snapshot }
        }
        return result
    }
}
