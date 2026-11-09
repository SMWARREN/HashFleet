// ActivityKit's Activity reference has incomplete Sendable annotations in the SDK.
// Keep all application ownership on MainActor and use its documented async update/end APIs.
#if canImport(ActivityKit) && !os(macOS)
@preconcurrency import ActivityKit
#endif
import Foundation
import Observation
import WidgetKit
import HashFleetCore

@MainActor @Observable
final class FleetGlanceCoordinator {
    private(set) var sharesWithWidgets: Bool
    private(set) var allowsWidgetRefresh: Bool
    private(set) var allowsAutomaticWidgetRefresh: Bool
    private(set) var widgetRefreshStatus = "Off. Widgets use saved readings only."
    private(set) var hasLiveActivity = false
    private(set) var isChangingActivity = false
    var error: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storage: FleetGlanceStorage
    @ObservationIgnored private let refreshStorage: FleetWidgetRefreshStorage
    @ObservationIgnored private var refreshPreparation = FleetWidgetRefreshPreparation()
    @ObservationIgnored private let isTesting: Bool
    @ObservationIgnored private let activityName: String
    @ObservationIgnored private var lastPublished: FleetGlance?
    @ObservationIgnored private var lastWidgetReloadAt: Date?
    private static let sharingKey = "app.hashfleet.shareWithWidgets"
    private static let refreshKey = "app.hashfleet.allowWidgetRefresh"
    private static let automaticRefreshKey = "app.hashfleet.allowAutomaticWidgetRefresh"
    private static let readyWidgetRefreshStatus = "Ready for local refresh for up to 24 hours. Stay on the miners' network. Unlock is required. Failures keep the last saved reading."
    static let widgetReloadMinimumInterval: TimeInterval = FleetGlance.freshnessInterval

    init(
        defaults: UserDefaults = .standard,
        storage: FleetGlanceStorage = .shared,
        refreshStorage: FleetWidgetRefreshStorage = .init(directory: nil),
        isTesting: Bool = false,
        activityName: String = "HashFleet"
    ) {
        self.defaults = defaults
        self.storage = storage
        self.refreshStorage = refreshStorage
        self.isTesting = isTesting
        self.activityName = activityName
        #if os(macOS)
        // The native Mac app owns its menu bar in-process, not through an iOS widget extension.
        sharesWithWidgets = false
        allowsWidgetRefresh = false
        allowsAutomaticWidgetRefresh = false
        #else
        let isSharing = defaults.bool(forKey: Self.sharingKey)
        let allowsLocalRefresh = isSharing && defaults.bool(forKey: Self.refreshKey)
        sharesWithWidgets = isSharing
        allowsWidgetRefresh = allowsLocalRefresh
        allowsAutomaticWidgetRefresh = allowsLocalRefresh && defaults.bool(forKey: Self.automaticRefreshKey)
        if allowsWidgetRefresh {
            widgetRefreshStatus = "Open Fleet and refresh all miners to prepare local refresh."
        }
        if !isTesting {
            hasLiveActivity = !activeActivities.isEmpty
            if !sharesWithWidgets { storage.clear() }
            if !allowsWidgetRefresh { revokeWidgetRefresh(status: "Off. Widgets use saved readings only.") }
        }
        #endif
    }

    var widgetStorageAvailable: Bool {
        #if os(macOS)
        false
        #else
        storage.isAvailable && !isTesting
        #endif
    }
    var activitiesAllowed: Bool {
        #if canImport(ActivityKit) && !os(macOS)
        !isTesting && ActivityAuthorizationInfo().areActivitiesEnabled
        #else
        false
        #endif
    }
    #if canImport(ActivityKit) && !os(macOS)
    private var activeActivities: [Activity<FleetActivityAttributes>] {
        Activity<FleetActivityAttributes>.activities.filter {
            $0.attributes.name == activityName && ($0.activityState == .active || $0.activityState == .stale)
        }
    }
    #endif

    func setWidgetSharing(_ enabled: Bool, glance: FleetGlance) {
        #if os(macOS)
        error = "Widgets are available in the iPhone and iPad app. This Mac app has an integrated menu bar."
        #else
        guard !isTesting else { return }
        if enabled && !storage.isAvailable {
            error =
                "The shared widget container is unavailable. Enable the same App Group for the app "
                + "and widget extension in Xcode Signing & Capabilities."
            return
        }
        sharesWithWidgets = enabled
        defaults.set(enabled, forKey: Self.sharingKey)
        if enabled {
            _ = storage.save(glance)
        } else {
            // Revoke the extension's transactional lease before clearing the legacy aggregate.
            revokeWidgetRefresh(status: "Off. Widgets use saved readings only.")
            defaults.set(false, forKey: Self.refreshKey)
            allowsWidgetRefresh = false
            defaults.set(false, forKey: Self.automaticRefreshKey)
            allowsAutomaticWidgetRefresh = false
            storage.clear()
        }
        // A deliberate opt-in/out is an explicit user action, so it gets an immediate reload.
        lastWidgetReloadAt = nil
        WidgetCenter.shared.reloadTimelines(ofKind: "HashFleet.Fleet")
        lastWidgetReloadAt = Date()
        #endif
    }

    /// Separate consent: ordinary widget sharing never grants access to local miner addresses.
    func setWidgetRefreshEnabled(
        _ enabled: Bool, devices: [MinerDevice], snapshots: [UUID: MinerSnapshot],
        isDemo: Bool, now: Date = Date()
    ) {
        #if !os(macOS)
        guard !isTesting else { return }
        guard !enabled || (defaults.bool(forKey: Self.sharingKey) && storage.isAvailable && !isDemo) else {
            error = "Enable widget sharing with a real fleet before allowing local widget refresh."
            return
        }
        defaults.set(enabled, forKey: Self.refreshKey)
        if !enabled { defaults.set(false, forKey: Self.automaticRefreshKey) }
        updateWidgetRefreshFleet(devices: devices, snapshots: snapshots, isDemo: isDemo, now: now)
        WidgetCenter.shared.reloadTimelines(ofKind: "HashFleet.Fleet")
        #endif
    }

    /// Existing permission covers taps only. Automatic local reads require this additional choice.
    func setAutomaticWidgetRefreshEnabled(
        _ enabled: Bool, devices: [MinerDevice], snapshots: [UUID: MinerSnapshot],
        isDemo: Bool, now: Date = Date()
    ) {
        #if !os(macOS)
        guard !isTesting else { return }
        guard !enabled || (defaults.bool(forKey: Self.sharingKey)
            && defaults.bool(forKey: Self.refreshKey) && storage.isAvailable && !isDemo) else {
            error = "Allow local widget refresh with a real fleet before enabling automatic refresh."
            return
        }
        defaults.set(enabled, forKey: Self.automaticRefreshKey)
        if !enabled, refreshStorage.load() != nil,
           !refreshStorage.setAutomaticRefreshEnabled(false, now: now) {
            error = "Automatic refresh could not be disabled. Reopen the app and retry."
        }
        updateWidgetRefreshFleet(devices: devices, snapshots: snapshots, isDemo: isDemo, now: now)
        WidgetCenter.shared.reloadTimelines(ofKind: "HashFleet.Fleet")
        #endif
    }

    /// Only the foreground app prepares identity pins. No network work happens in this method.
    func updateWidgetRefreshFleet(
        devices: [MinerDevice], snapshots: [UUID: MinerSnapshot], isDemo: Bool,
        isForeground: Bool = true, now: Date = Date()
    ) {
        #if !os(macOS)
        guard !isTesting else { return }
        let targets = refreshPreparation.targets(devices: devices, snapshots: snapshots, isDemo: isDemo, now: now)
        sharesWithWidgets = defaults.bool(forKey: Self.sharingKey)
        allowsWidgetRefresh = sharesWithWidgets && defaults.bool(forKey: Self.refreshKey)
        allowsAutomaticWidgetRefresh = allowsWidgetRefresh && defaults.bool(forKey: Self.automaticRefreshKey)
        guard allowsWidgetRefresh else {
            revokeWidgetRefresh(status: "Off. Widgets use saved readings only.")
            return
        }
        guard !isDemo else {
            revokeWidgetRefresh(status: "Open Fleet and refresh all miners to prepare. Requires 1–16 credential-free ASICs, private "
                + "IPv4 addresses and fresh matching identities. Demo is not supported.")
            return
        }
        // Only a complete foreground observation can grant or renew prepared local reads.
        if isForeground, let targets {
            guard refreshStorage.configure(targets: targets, now: now, automatically: allowsAutomaticWidgetRefresh) else {
                revokeWidgetRefresh(status: "Refresh could not be prepared. Check App Group setup and distinct local miner identities.")
                return
            }
            widgetRefreshStatus = readyWidgetRefreshStatus
            return
        }
        // An app-process widget intent can cold-start before the store has live frames. Keep
        // the existing exact pins and saved result, rather than deleting permission on startup.
        // Changed selections, explicit opt-out, Demo and fresh contradictory identities still revoke.
        if let state = refreshStorage.load(), FleetWidgetRefreshPreparation.matchesPreparedFleet(
            state.configuration, devices: devices, snapshots: snapshots, now: now
        ) {
            // A deliberate foreground choice may change auto consent on existing valid pins.
            // A passive background owner may only revoke it, never turn it on or renew pins.
            if isForeground || !allowsAutomaticWidgetRefresh, state.configuration.isEnabled(at: now),
               (state.configuration.automaticRefreshGeneration != nil) != allowsAutomaticWidgetRefresh,
               !refreshStorage.setAutomaticRefreshEnabled(allowsAutomaticWidgetRefresh, now: now) {
                widgetRefreshStatus = "Automatic refresh permission could not be changed. Reopen the app and retry."
                error = widgetRefreshStatus
                return
            }
            widgetRefreshStatus = state.configuration.isEnabled(at: now)
                ? readyWidgetRefreshStatus
                : "Local refresh needs preparation in Fleet. The last saved reading is retained."
            return
        }
        revokeWidgetRefresh(status: "Open Fleet and refresh all miners to prepare. Requires 1–16 credential-free ASICs, private IPv4 addresses and fresh matching identities. Demo is not supported.")
        #endif
    }

    private var readyWidgetRefreshStatus: String {
        allowsAutomaticWidgetRefresh
            ? "Automatic local refresh is ready for up to 24 hours. iOS chooses update times, which may be "
                + "several minutes apart or delayed. Stay on the miners' network. Failed reads keep their original "
                + "time."
            : Self.readyWidgetRefreshStatus
    }

    private func revokeWidgetRefresh(status: String) {
        if refreshStorage.revoke() {
            widgetRefreshStatus = status
        } else {
            widgetRefreshStatus = "Local refresh permission could not be removed. Reopen the app and retry turning it off."
            error = widgetRefreshStatus
        }
    }

    /// Publishes the latest aggregate to the shared widget cache. A foreground bootstrap may force
    /// one WidgetKit reload even when its value is inside the normal freshness window. Live frames
    /// should use the default so WidgetKit's reload budget remains protected.
    func publish(
        _ glance: FleetGlance,
        menuBarMiners: [FleetMenuBarMinerSummary] = [],
        menuBarSnapshot: FleetMenuBarSnapshot? = nil,
        publishAggregate: Bool = true,
        forceWidgetReload: Bool = false
    ) async {
        #if !os(macOS)
        guard !isTesting, !Task.isCancelled else { return }
        if ProcessInfo.processInfo.isiOSAppOnMac || ProcessInfo.processInfo.isMacCatalystApp {
            if publishAggregate { _ = FleetMenuBarGlanceStorage.shared.save(glance) }
            if !FleetMenuBarSnapshotStorage.shared.save(menuBarSnapshot ?? FleetMenuBarSnapshot(
                glance: glance, miners: menuBarMiners
            )) {
                error = "Could not save the menu-bar snapshot. The companion may show an earlier reading."
            }
        }
        // The widget payload has no completeness fields. Keep its existing strict policy,
        // independently of the richer menu-bar payload that was just published.
        guard publishAggregate else { return }
        // A background owner can outlive a foreground owner's opt-out while its read awaits.
        // Re-read consent immediately before the synchronous cache write, not only at init.
        sharesWithWidgets = defaults.bool(forKey: Self.sharingKey)
        if sharesWithWidgets {
            if !storage.save(glance) {
                error = "Could not save the shared widget snapshot. Widgets may still show an earlier reading."
            }
            // Save every valid live frame, but do not burn WidgetKit's reload budget at the
            // firmware's frame cadence. A new coordinator after foreground entry can still issue
            // an immediate bootstrap reload, while subsequent live frames are freshness-gated.
            if forceWidgetReload
                || (lastPublished != glance && Self.widgetReloadAllowed(at: Date(), lastReloadAt: lastWidgetReloadAt)) {
                WidgetCenter.shared.reloadTimelines(ofKind: "HashFleet.Fleet")
                lastWidgetReloadAt = Date()
            }
        }
        lastPublished = glance
        for activity in activeActivities {
            // Never silently replace an opted-in real activity with sample readings or an empty fleet.
            if glance.minerCount == 0 || activity.content.state.glance.isDemo != glance.isDemo {
                await activity.end(nil, dismissalPolicy: .immediate)
            } else if glance.isValid && glance.updatedAt > activity.content.state.glance.updatedAt {
                await activity.update(content(for: glance))
            }
        }
        hasLiveActivity = !activeActivities.isEmpty
        #endif
    }

    static func menuBarMiners(
        devices: [MinerDevice],
        snapshots: [UUID: MinerSnapshot],
        isDemo: Bool
    ) -> [FleetMenuBarMinerSummary] {
        FleetStatusTickerModel(devices: devices, snapshots: snapshots, isDemo: isDemo).items.map { item in
            let status: FleetMenuBarMinerStatus
            switch item.status {
            case .connecting: status = .connecting
            case .reconnecting: status = .reconnecting
            case .offline: status = .offline
            case .online: status = .online
            }
            var summary = FleetMenuBarMinerSummary(
                id: item.id,
                name: item.name,
                status: status,
                segments: item.segments,
                notices: item.notices,
                isSimulated: item.isSimulated
            )
            summary.sessionBest = FleetActivityPresentation.sessionBest(
                snapshot: snapshots[item.id], isDemo: isDemo)
            return summary
        }
    }

    static func menuBarSnapshot(
        devices: [MinerDevice], snapshots: [UUID: MinerSnapshot], updatedAt: Date, isDemo: Bool
    ) -> FleetMenuBarSnapshot {
        let online = devices.filter { device in
            guard let snapshot = snapshots[device.id] else { return false }
            return snapshot.info != nil && snapshot.error == nil && !snapshot.isCached && !snapshot.isReconnecting
        }
        let totals = FleetTotals(snapshots: online.compactMap { snapshots[$0.id] })
        // Different algorithms must never be summed, even after XMRig is re-enabled.
        let hashrateComplete = totals.hashrate.isComplete && Set(online.map(\.kind)).count <= 1
        let powerComplete = totals.power.isComplete
        return FleetMenuBarSnapshot(
            glance: FleetGlance(
                updatedAt: updatedAt, onlineCount: online.count, minerCount: devices.count,
                hashrateGHs: hashrateComplete ? totals.hashrate.value : 0,
                powerWatts: powerComplete ? totals.power.value : 0, isDemo: isDemo
            ),
            miners: menuBarMiners(devices: devices, snapshots: snapshots, isDemo: isDemo),
            hashrateIsComplete: hashrateComplete, powerIsComplete: powerComplete
        )
    }

    static func widgetReloadAllowed(at date: Date, lastReloadAt: Date?) -> Bool {
        guard let lastReloadAt else { return true }
        return date.timeIntervalSince(lastReloadAt) >= widgetReloadMinimumInterval
    }

    func start(_ glance: FleetGlance) async {
        #if canImport(ActivityKit) && !os(macOS)
        guard !isChangingActivity, !isTesting else { return }
        guard activitiesAllowed else {
            error = "Live Activities are not available. Check Hash Fleet's Live Activities permission in Settings."
            return
        }
        guard glance.minerCount > 0, !glance.isStale(at: Date()) else {
            error = "Refresh your fleet in the app before starting a Live Activity."
            return
        }
        isChangingActivity = true
        defer { isChangingActivity = false }
        do {
            if activeActivities.isEmpty {
                var attributes = FleetActivityAttributes(name: activityName)
                if !glance.isDemo, let state = refreshStorage.load(),
                   state.configuration.isEnabled(at: Date()),
                   state.configuration.targets.count == glance.minerCount {
                    attributes.refreshGeneration = state.configuration.generation
                }
                _ = try Activity<FleetActivityAttributes>.request(
                    attributes: attributes,
                    content: content(for: glance),
                    pushType: nil
                )
            } else {
                for activity in activeActivities { await activity.update(content(for: glance)) }
            }
            hasLiveActivity = !activeActivities.isEmpty
        } catch { self.error = error.localizedDescription }
        #else
        error = "Live Activities are available in the iPhone and iPad app, not on macOS."
        #endif
    }

    func stop() async {
        #if canImport(ActivityKit) && !os(macOS)
        guard !isTesting, !isChangingActivity else { return }
        isChangingActivity = true
        defer { isChangingActivity = false }
        for activity in Activity<FleetActivityAttributes>.activities where activity.attributes.name == activityName {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        hasLiveActivity = false
        #endif
    }

    #if canImport(ActivityKit) && !os(macOS)
    private func content(for glance: FleetGlance) -> ActivityContent<FleetActivityAttributes.ContentState> {
        ActivityContent(
            state: .init(glance: glance),
            staleDate: glance.updatedAt.addingTimeInterval(FleetGlance.freshnessInterval)
        )
    }
    #endif
}
