import Foundation
#if canImport(ActivityKit) && !os(macOS)
@preconcurrency import ActivityKit
#endif

/// A receipt for one completed local read. It is not a new grant of network or activity consent.
struct FleetActivityRefreshPublication: Sendable, Equatable {
    let generation: UUID
    let glance: FleetGlance
    var automaticRefreshGeneration: UUID?

    func hasCurrentPermission(in storage: FleetWidgetRefreshStorage, at now: Date) -> Bool {
        guard !Task.isCancelled, let state = storage.load() else { return false }
        return state.configuration.generation == generation && state.configuration.isEnabled(at: now)
            && (automaticRefreshGeneration == nil || automaticRefreshGeneration == state.configuration.automaticRefreshGeneration)
            && !glance.isDemo && glance.minerCount == state.configuration.targets.count
    }

    func isAuthorized(in storage: FleetWidgetRefreshStorage, at now: Date) -> Bool {
        guard !Task.isCancelled, let state = storage.load(), state.lastOutcome == .refreshed,
              state.configuration.generation == generation, state.configuration.isEnabled(at: now),
              state.glance == glance, !glance.isDemo, !glance.isStale(at: now),
              glance.onlineCount == glance.minerCount,
              glance.minerCount == state.configuration.targets.count else { return false }
        guard automaticRefreshGeneration == nil
            || automaticRefreshGeneration == state.configuration.automaticRefreshGeneration else { return false }
        return true
    }

    func canReplace(_ previous: FleetGlance, refreshGeneration: UUID?) -> Bool {
        refreshGeneration == generation && previous.isValid && !previous.isDemo && !glance.isDemo
            && previous.minerCount == glance.minerCount && glance.updatedAt > previous.updatedAt
    }
}

enum FleetActivityRefreshHandoff {
    /// LiveActivityIntent executes this in the app process. Never request or renew an activity here.
    @MainActor static func deliver(
        _ publication: FleetActivityRefreshPublication,
        storage: FleetWidgetRefreshStorage = .shared,
        activityName: String = "HashFleet"
    ) async {
        #if canImport(ActivityKit) && !os(macOS)
        for activity in Activity<FleetActivityAttributes>.activities {
            guard activity.attributes.name == activityName,
                  activity.activityState == .active || activity.activityState == .stale,
                  publication.isAuthorized(in: storage, at: Date()),
                  publication.canReplace(activity.content.state.glance,
                      refreshGeneration: activity.attributes.refreshGeneration) else { continue }
            await activity.update(ActivityContent(state: .init(glance: publication.glance),
                staleDate: publication.glance.updatedAt.addingTimeInterval(FleetGlance.freshnessInterval)))
            // Revocation can happen while ActivityKit suspends. Do not leave that late result on
            // the Lock Screen. End only this old activity, never an unrelated replacement.
            if !publication.hasCurrentPermission(in: storage, at: Date()) {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        #endif
    }
}
