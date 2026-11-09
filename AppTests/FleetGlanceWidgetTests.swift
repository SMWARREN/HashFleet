import ActivityKit
import Foundation
import Testing
@testable import HashFleet

extension FleetGlanceTests {
    @Test func widgetReloadGateAllowsBootstrapAndThrottlesLiveFrames() {
        let first = timestamp
        #expect(FleetGlanceCoordinator.widgetReloadAllowed(at: first, lastReloadAt: nil))
        #expect(
            FleetGlanceCoordinator.widgetReloadAllowed(
                at: first.addingTimeInterval(FleetGlanceCoordinator.widgetReloadMinimumInterval - 0.001),
                lastReloadAt: first
            ) == false
        )
        #expect(
            FleetGlanceCoordinator.widgetReloadAllowed(
                at: first.addingTimeInterval(FleetGlanceCoordinator.widgetReloadMinimumInterval),
                lastReloadAt: first
            )
        )
    }

    @Test(arguments: [
        "negativeOnline", "negativeMiners", "onlineExceedsTotal", "negativeHashrate",
        "negativePower", "infiniteHashrate", "nanPower", "invalidDate"
    ])
    func invalidAggregatesAreStaleAndCannotReplaceValidCache(kind: String) throws {
        var invalid = sample()
        switch kind {
        case "negativeOnline": invalid.onlineCount = -1
        case "negativeMiners": invalid.minerCount = -1
        case "onlineExceedsTotal": invalid.onlineCount = invalid.minerCount + 1
        case "negativeHashrate": invalid.hashrateGHs = -0.1
        case "negativePower": invalid.powerWatts = -0.1
        case "infiniteHashrate": invalid.hashrateGHs = .infinity
        case "nanPower": invalid.powerWatts = .nan
        case "invalidDate": invalid.updatedAt = Date(timeIntervalSince1970: .infinity)
        default: Issue.record("Unrecognized invalid fixture: \(kind)")
        }
        #expect(invalid.isValid == false)
        #expect(invalid.isStale(at: timestamp))
        let glanceEnv = try fixture()
        let storage = glanceEnv.storage
        let defaults = glanceEnv.defaults
        let suite = glanceEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(storage.save(sample()))
        #expect(storage.save(invalid) == false)
        #expect(storage.load() == sample())
    }

    @Test func syntacticallyValidButImpossibleCachedCountsLoadEmpty() throws {
        let glanceEnv = try fixture()
        let storage = glanceEnv.storage
        let defaults = glanceEnv.defaults
        let suite = glanceEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        storage.save(sample())
        let key = try storedKey(in: defaults, suite: suite)
        var impossible = sample()
        impossible.onlineCount = impossible.minerCount + 1
        defaults.set(try JSONEncoder().encode(impossible), forKey: key)
        #expect(storage.load() == .empty)
    }

    private func freshLiveGlance() -> FleetGlance {
        FleetGlance(updatedAt: Date(), onlineCount: 1, minerCount: 1, hashrateGHs: 999, powerWatts: 15, isDemo: false)
    }

    @Test(arguments: [false, true])
    func testModeCoordinatorCannotChangePreferencesCacheOrActivities(wasSharing: Bool) async throws {
        let glanceEnv = try fixture()
        let storage = glanceEnv.storage
        let defaults = glanceEnv.defaults
        let suite = glanceEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = sample(isDemo: true)
        #expect(storage.save(original))
        let cacheKey = try storedKey(in: defaults, suite: suite)
        let originalBytes = try #require(defaults.data(forKey: cacheKey))
        let sharingKey = "app.hashfleet.shareWithWidgets"
        defaults.set(wasSharing, forKey: sharingKey)
        let originalDomain = try #require(defaults.persistentDomain(forName: suite))

        // Read existing system state without creating, updating or ending an activity.
        // A private name also prevents accidentally targeting normal user activities
        // if a future refactor weakens an isTesting guard.
        let originalActivities = activityStates()
        let coordinator = FleetGlanceCoordinator(
            defaults: defaults,
            storage: storage,
            isTesting: true,
            activityName: "HashFleet Isolation Test \(suite)"
        )
        let fresh = freshLiveGlance()

        @MainActor func expectNoEffects() {
            #expect(coordinator.sharesWithWidgets == wasSharing)
            #expect(coordinator.hasLiveActivity == false)
            #expect(coordinator.isChangingActivity == false)
            #expect(coordinator.widgetStorageAvailable == false)
            #expect(coordinator.activitiesAllowed == false)
            #expect(coordinator.error == nil)
            #expect(defaults.bool(forKey: sharingKey) == wasSharing)
            #expect(defaults.data(forKey: cacheKey) == originalBytes)
            #expect(storage.load() == original)
            #expect(
                NSDictionary(dictionary: defaults.persistentDomain(forName: suite) ?? [:])
                    .isEqual(to: originalDomain)
            )
            #expect(activityStates() == originalActivities)
        }

        expectNoEffects()  // Initialization itself must not clear a pre-seeded cache.
        coordinator.setWidgetSharing(true, glance: fresh)
        expectNoEffects()
        coordinator.setWidgetSharing(false, glance: fresh)
        expectNoEffects()
        await coordinator.publish(fresh)
        expectNoEffects()
        await coordinator.start(fresh)
        expectNoEffects()
        await coordinator.stop()
        expectNoEffects()
    }

    private struct ObservedActivity: Equatable {
        let name: String
        let state: String
        let content: FleetActivityAttributes.ContentState
    }

    private func activityStates() -> [String: ObservedActivity] {
        Dictionary(
            uniqueKeysWithValues: Activity<FleetActivityAttributes>.activities.map {
                (
                    $0.id,
                    ObservedActivity(
                        name: $0.attributes.name,
                        state: String(describing: $0.activityState),
                        content: $0.content.state
                    )
                )
            }
        )
    }
}
