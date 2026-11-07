import Foundation
import HashFleetCore

/// One delivery owner for foreground monitoring and background refresh. Detection is durable, while
/// system delivery and in-app presentation are tracked separately so a cold launch can show the
/// same event without treating it as a second detection.
@MainActor
enum FleetNotificationDelivery {
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
        presentInApp: (FleetNotificationEvent) -> Void = { _ in }
    ) -> [MinerTemperatureAlertEvent] {
        let pending = store.drainPendingNotificationEvents()
        guard !store.isDemo else { return [] }
        let deviceIDs = Set(store.visibleDevices.map(\.id))
        var inAppTemperatures: [MinerTemperatureAlertEvent] = []
        let postHandlers = PostHandlers(
            block: postBlock, bestShare: postBestShare, temperature: postTemperature,
            stateChange: postStateChange, metricAlert: postMetricAlert, power: postPower
        )

        func route(_ event: FleetNotificationEvent) {
            guard deviceIDs.contains(event.deviceID), isEnabled(event, in: store) else {
                store.markSystemNotificationDelivered(for: event)
                return
            }
            guard isActive else {
                deliver(event, from: store) {
                    post(event, using: postHandlers)
                }
                return
            }
            // The app is open: show it in the app only, never also as a push.
            store.markSystemNotificationDelivered(for: event)
            if case .temperature(let temperature) = event {
                inAppTemperatures.append(temperature)
            } else {
                showInApp(event, from: store, presentInApp: presentInApp)
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
        presentInApp: (FleetNotificationEvent) -> Void = { _ in }
    ) {
        guard !store.isDemo else { return }
        let deviceIDs = Set(store.visibleDevices.map(\.id))
        let superseded = supersededStatusEntryIDs(in: store.notificationInbox)
        for entry in store.undeliveredSystemNotificationEntries {
            // Status alerts share one notification slot per miner. Replaying an older one after a
            // newer one would overwrite the current status with a stale message.
            guard deviceIDs.contains(entry.event.deviceID), !superseded.contains(entry.id) else {
                store.markSystemNotificationDelivered(for: entry.event)
                continue
            }
            guard isEnabled(entry.event, in: store) else {
                store.markSystemNotificationDelivered(for: entry.event)
                continue
            }
            if isActive {
                store.markSystemNotificationDelivered(for: entry.event)
                if !entry.inAppDelivered { showInApp(entry.event, from: store, presentInApp: presentInApp) }
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
    private static func showInApp(
        _ event: FleetNotificationEvent,
        from store: FleetStore,
        presentInApp: (FleetNotificationEvent) -> Void
    ) {
        guard !store.isInAppNotificationDelivered(event) else { return }
        store.markInAppNotificationDelivered(for: event)
        presentInApp(event)
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
