import Foundation
import HashFleetCore

/// One delivery owner for foreground monitoring and background refresh. Detection is durable, while
/// system delivery and in-app presentation are tracked separately so a cold launch can show the
/// same event without treating it as a second detection.
@MainActor
enum FleetNotificationDelivery {
    // A synchronous acceptance callback may re-enter delivery. Do not drain or replay this
    // owner again until the first handoff has returned and its journal flag is committed.
    private static var acceptingStores: Set<ObjectIdentifier> = []
    private static var recordAcceptanceTasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    /// The synchronous router first journals record acceptance as pending, while delivering
    /// safety alerts immediately. One pump then commits records in journal order. Concurrent
    /// routing can append pending records during a write without starting a second handoff.
    /// A failed write stops this pass; a later delivery/lifecycle trigger retries the same head.
    @discardableResult
    static func schedulePendingRecordAcceptances(
        from store: FleetStore,
        accept: @escaping @MainActor (FleetNotificationEvent) async -> Bool
    ) -> Task<Void, Never> {
        let owner = ObjectIdentifier(store)
        if let existing = recordAcceptanceTasks[owner] { return existing }
        let task = Task { @MainActor in
            defer { recordAcceptanceTasks.removeValue(forKey: owner) }
            guard !store.isDemo else { return }
            while !Task.isCancelled, let entry = store.notificationInbox.first(where: {
                $0.inAppAcceptancePending == true && !$0.inAppDelivered && isRecord($0.event)
            }) {
                guard store.visibleDevices.contains(where: { $0.id == entry.event.deviceID }),
                      isEnabled(entry.event, in: store) else {
                    store.markInAppNotificationDelivered(for: entry.event)
                    continue
                }
                // This await returns only after the queue transaction commits or fails.
                guard await accept(entry.event) else { return }
                store.markInAppNotificationDelivered(for: entry.event)
            }
        }
        recordAcceptanceTasks[owner] = task
        return task
    }

    private struct PostHandlers {
        let block: (MinerBlockFoundEvent) -> Void
        let bestShare: (MinerBestShareEvent) -> Void
        let temperature: (MinerTemperatureAlertEvent) -> Void
        let stateChange: (MinerStateChangeEvent) -> Void
        let metricAlert: (MinerMetricAlertEvent) -> Void
        let power: (MinerPowerAlertEvent) -> Void
    }

    /// Routes every drained event to exactly one channel. While the app is active the in-app
    /// surface owns it (status alerts and illustrated record popups via `presentInApp`,
    /// temperatures via the returned list) and nothing is posted to
    /// iOS. Otherwise a system notification is posted and the event is marked as already shown,
    /// so opening the app later never repeats it as an in-app banner.
    @discardableResult
    static func consume(
        from store: FleetStore,
        isActive: Bool,
        postBlock: @escaping (MinerBlockFoundEvent) -> Void = { FleetLocalNotifications.post($0) },
        postBestShare: @escaping (MinerBestShareEvent) -> Void = { FleetLocalNotifications.post($0) },
        postTemperature: @escaping (MinerTemperatureAlertEvent) -> Void = { FleetLocalNotifications.post($0) },
        postStateChange: @escaping (MinerStateChangeEvent) -> Void = { FleetLocalNotifications.post($0) },
        postMetricAlert: @escaping (MinerMetricAlertEvent) -> Void = { FleetLocalNotifications.post($0) },
        postPower: @escaping (MinerPowerAlertEvent) -> Void = { FleetLocalNotifications.post($0) },
        presentInApp: @MainActor (FleetNotificationEvent) -> Void = { _ in },
        acceptInApp: (@MainActor (FleetNotificationEvent) -> Bool)? = nil
    ) -> [MinerTemperatureAlertEvent] {
        guard !acceptingStores.contains(ObjectIdentifier(store)) else { return [] }
        let pending = store.drainPendingNotificationEvents()
        guard !store.isDemo else { return [] }
        let deviceIDs = Set(store.visibleDevices.map(\.id))
        var inAppTemperatures: [MinerTemperatureAlertEvent] = []
        var acceptanceBlocked = false
        if isActive, let acceptInApp {
            acceptanceBlocked = retryPendingAcceptances(from: store, acceptInApp: acceptInApp)
        }
        let postHandlers = PostHandlers(
            block: postBlock, bestShare: postBestShare, temperature: postTemperature,
            stateChange: postStateChange, metricAlert: postMetricAlert, power: postPower
        )

        func route(_ event: FleetNotificationEvent) {
            guard deviceIDs.contains(event.deviceID), isEnabled(event, in: store) else {
                store.markSystemNotificationDelivered(for: event)
                if store.notificationInbox.contains(where: {
                    ($0.id == event.id || $0.dedupeKey == event.dedupeKey) && $0.inAppAcceptancePending == true
                }) { store.markInAppNotificationDelivered(for: event) }
                return
            }
            guard isActive else {
                deliver(event, from: store) {
                    post(event, using: postHandlers)
                }
                return
            }
            // The app is open: show it in the app only, never also as a push.
            if case .temperature(let temperature) = event {
                store.markSystemNotificationDelivered(for: event)
                inAppTemperatures.append(temperature)
                if acceptInApp != nil { store.markInAppNotificationDelivered(for: event) }
            } else if !showInApp(event, from: store, presentInApp: presentInApp,
                                 acceptInApp: acceptInApp, deferAcceptance: acceptanceBlocked && isRecord(event)),
                      isRecord(event) {
                acceptanceBlocked = true
            }
        }

        let events = pending.blocksFound.map(FleetNotificationEvent.blockFound)
            + pending.bestShares.map(FleetNotificationEvent.bestShare)
            + pending.stateChanges.map(FleetNotificationEvent.stateChange)
            + pending.metricAlerts.map(FleetNotificationEvent.metricAlert)
            + pending.powerAlerts.map(FleetNotificationEvent.power)
            + pending.temperatures.map(FleetNotificationEvent.temperature)
        events.forEach(route)
        return inAppTemperatures
    }

    /// Replays journal entries that were detected but not handed to iOS before a background task
    /// expired or the process was suspended. Event IDs remain stable across launches.
    /// When `isActive`, the app is open, so unsent entries are shown in the app instead of being
    /// posted late as pushes. Every milestone uses the same illustrated presentation route.
    static func replayUndeliveredSystemNotifications(
        from store: FleetStore,
        isActive: Bool = false,
        presentInApp: @MainActor (FleetNotificationEvent) -> Void = { _ in },
        acceptInApp: (@MainActor (FleetNotificationEvent) -> Bool)? = nil
    ) {
        guard !store.isDemo, !acceptingStores.contains(ObjectIdentifier(store)) else { return }
        let deviceIDs = Set(store.visibleDevices.map(\.id))
        let superseded = supersededStatusEntryIDs(in: store.notificationInbox)
        var acceptanceBlocked = false
        let entries = store.notificationInbox.filter {
            !$0.systemDelivered || (isActive && acceptInApp != nil
                && $0.inAppAcceptancePending == true && !$0.inAppDelivered)
        }
        for entry in entries {
            // Status alerts share one notification slot per miner. Replaying an older one after a
            // newer one would overwrite the current status with a stale message.
            guard deviceIDs.contains(entry.event.deviceID), !superseded.contains(entry.id) else {
                store.markSystemNotificationDelivered(for: entry.event)
                if entry.inAppAcceptancePending == true { store.markInAppNotificationDelivered(for: entry.event) }
                continue
            }
            guard isEnabled(entry.event, in: store) else {
                store.markSystemNotificationDelivered(for: entry.event)
                if entry.inAppAcceptancePending == true { store.markInAppNotificationDelivered(for: entry.event) }
                continue
            }
            if isActive {
                if !entry.inAppDelivered,
                   !showInApp(entry.event, from: store, presentInApp: presentInApp,
                              acceptInApp: acceptInApp, deferAcceptance: acceptanceBlocked && isRecord(entry.event)) {
                    if isRecord(entry.event) { acceptanceBlocked = true }
                } else {
                    store.markSystemNotificationDelivered(for: entry.event)
                }
                continue
            }
            deliver(entry.event, from: store) { postSystemNotification(entry.event) }
        }
    }

    /// Whether the user currently wants this kind of alert for this miner.
    static func isEnabled(_ event: FleetNotificationEvent, in store: FleetStore) -> Bool {
        let preferences = store.preferences
        switch event {
        case .blockFound: return preferences.blockNotificationsEnabled
        case .bestShare(let event):
            return event.kind == .session
                ? preferences.bestShareNotificationsEnabled && preferences.sessionBestNotificationsEnabled
                : preferences.bestShareNotificationsEnabled
        case .stateChange: return preferences.stateChangeNotificationsEnabled
        case .metricAlert: return preferences.metricAlertNotificationsEnabled
        case .power(let event):
            return preferences.powerAlertNotificationsEnabled && store.powerAlerts.policy(for: event.deviceID).isEnabled
        case .temperature(let event): return store.temperatureAlerts.policy(for: event.deviceID).isEnabled
        }
    }

    private static func postSystemNotification(_ event: FleetNotificationEvent) {
        post(event, using: PostHandlers(
            block: FleetLocalNotifications.post, bestShare: FleetLocalNotifications.post,
            temperature: FleetLocalNotifications.post, stateChange: FleetLocalNotifications.post,
            metricAlert: FleetLocalNotifications.post, power: FleetLocalNotifications.post
        ))
    }

    private static func post(_ event: FleetNotificationEvent, using handlers: PostHandlers) {
        switch event {
        case .blockFound(let event): handlers.block(event)
        case .bestShare(let event): handlers.bestShare(event)
        case .temperature(let event): handlers.temperature(event)
        case .stateChange(let event): handlers.stateChange(event)
        case .metricAlert(let event): handlers.metricAlert(event)
        case .power(let event): handlers.power(event)
        }
    }

    /// The notification slot a status alert occupies, matching the identifiers built by the
    /// notification content types. Milestones keep one notification per event and return nil.
    nonisolated static func statusSlot(for event: FleetNotificationEvent) -> String? {
        switch event {
        case .stateChange(let event): "state|\(event.deviceID.uuidString)"
        case .temperature(let event): "temperature|\(event.deviceID.uuidString)"
        case .power(let event): "power|\(event.deviceID.uuidString)"
        case .metricAlert(let event): "metric|\(event.deviceID.uuidString)|\(event.kind.rawValue)"
        case .bestShare, .blockFound: nil
        }
    }

    /// Entries whose slot already holds a newer event. They must never be posted late.
    nonisolated static func supersededStatusEntryIDs(in inbox: [FleetNotificationInboxEntry]) -> Set<UUID> {
        var newestBySlot: [String: FleetNotificationInboxEntry] = [:]
        for entry in inbox {
            guard let slot = statusSlot(for: entry.event) else { continue }
            if let current = newestBySlot[slot], current.event.occurredAt > entry.event.occurredAt { continue }
            newestBySlot[slot] = entry
        }
        let newestIDs = Set(newestBySlot.values.map(\.id))
        return Set(inbox.compactMap { entry in
            statusSlot(for: entry.event) != nil && !newestIDs.contains(entry.id) ? entry.id : nil
        })
    }

    /// One app-wide owner receives every event, including session, all-time and block records.
    /// It chooses the illustrated record popup rather than treating a session as a small banner.
    @discardableResult
    private static func showInApp(
        _ event: FleetNotificationEvent,
        from store: FleetStore,
        presentInApp: @MainActor (FleetNotificationEvent) -> Void,
        acceptInApp: (@MainActor (FleetNotificationEvent) -> Bool)? = nil,
        deferAcceptance: Bool = false
    ) -> Bool {
        guard !store.isInAppNotificationDelivered(event) else {
            store.markSystemNotificationDelivered(for: event)
            return true
        }
        guard let acceptInApp else {
            // Preserve the legacy callback contract, including reentrant once-only delivery.
            store.markSystemNotificationDelivered(for: event)
            store.markInAppNotificationDelivered(for: event)
            presentInApp(event)
            return true
        }
        let canonical = store.ensureNotificationEntry(for: event).event
        store.markInAppNotificationAcceptancePending(for: canonical)
        store.markSystemNotificationDelivered(for: canonical)
        guard !deferAcceptance else { return false }
        let owner = ObjectIdentifier(store)
        guard acceptingStores.insert(owner).inserted else { return false }
        defer { acceptingStores.remove(owner) }
        guard acceptInApp(canonical) else { return false }
        store.markInAppNotificationDelivered(for: canonical)
        return true
    }

    /// Returns true when an older declined handoff must keep newer records behind it. Only the
    /// explicit marker is retried, not ambiguous legacy system-only delivery flags.
    private static func retryPendingAcceptances(
        from store: FleetStore,
        acceptInApp: @escaping @MainActor (FleetNotificationEvent) -> Bool
    ) -> Bool {
        let deviceIDs = Set(store.visibleDevices.map(\.id))
        let superseded = supersededStatusEntryIDs(in: store.notificationInbox)
        var recordsBlocked = false
        for entry in store.notificationInbox where entry.inAppAcceptancePending == true && !entry.inAppDelivered {
            guard deviceIDs.contains(entry.event.deviceID), !superseded.contains(entry.id),
                  isEnabled(entry.event, in: store) else {
                store.markSystemNotificationDelivered(for: entry.event)
                store.markInAppNotificationDelivered(for: entry.event)
                continue
            }
            if !showInApp(entry.event, from: store, presentInApp: { _ in }, acceptInApp: acceptInApp,
                          deferAcceptance: recordsBlocked && isRecord(entry.event)), isRecord(entry.event) {
                recordsBlocked = true
            }
        }
        return recordsBlocked
    }

    private static func isRecord(_ event: FleetNotificationEvent) -> Bool {
        switch event {
        case .bestShare, .blockFound: true
        case .temperature, .power, .stateChange, .metricAlert: false
        }
    }

    private static func deliver(
        _ event: FleetNotificationEvent,
        from store: FleetStore,
        post: () -> Void
    ) {
        guard store.shouldPostSystemNotification(for: event) else { return }
        post()
        store.markSystemNotificationDelivered(for: event)
        // A pushed event is never repeated as an in-app banner or celebration later.
        store.markInAppNotificationDelivered(for: event)
    }
}

/// Delivery runs after a refresh and whenever an alert is queued outside a refresh (a live
/// socket outage records a failure without touching `lastRefresh`).
struct FleetNotificationDeliveryTrigger: Equatable {
    let refresh: Date?
    let queued: Date?
}

extension FleetStore {
    var notificationDeliveryTrigger: FleetNotificationDeliveryTrigger {
        FleetNotificationDeliveryTrigger(refresh: lastRefresh, queued: pendingNotificationsChangedAt)
    }
}
