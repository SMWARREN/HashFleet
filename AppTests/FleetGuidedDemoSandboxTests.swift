import Foundation
import Testing
@testable import HashFleet

@MainActor
struct FleetGuidedDemoSandboxTests {
    @Test func sandboxUsesUniquePrivateDefaultsAndNeverTouchesStandard() async {
        // Seed a sentinel in shared defaults to prove the sandbox cannot observe or overwrite it.
        UserDefaults.standard.set("original", forKey: "tour-sandbox-probe")
        defer { UserDefaults.standard.removeObject(forKey: "tour-sandbox-probe") }

        let sandbox = FleetGuidedDemoSandbox()
        defer { sandbox.cleanup() }

        #expect(sandbox.suiteName.hasPrefix("app.hashfleet.tour-sandbox."))
        #expect(UserDefaults(suiteName: sandbox.suiteName) != nil)

        // Tour suppression is marked in the private suite only.
        #expect(sandbox.store.preferences.hasSeenFeatureTour)
        #expect(sandbox.store.preferences.suppressFeatureTour)
        #expect(!sandbox.store.preferences.shouldShowFeatureTour)

        // Shared defaults are untouched by the sandbox's tour markers.
        let sharedProbe = UserDefaults.standard
        #expect(sharedProbe.string(forKey: "tour-sandbox-probe") == "original")
    }

    @Test func demoFleetFixturesLoadAndInsightsPrepareFillsFixtures() async {
        let sandbox = FleetGuidedDemoSandbox()
        defer { sandbox.cleanup() }

        #expect(sandbox.store.isDemo)
        #expect(!sandbox.store.devices.isEmpty)
        #expect(!sandbox.store.snapshots.isEmpty)

        await sandbox.prepare()
        #expect(sandbox.insights.network != nil)
        #expect(sandbox.insights.pool != nil)
    }

    @Test func twoSandboxesAreIndependent() async throws {
        let first = FleetGuidedDemoSandbox()
        let second = FleetGuidedDemoSandbox()
        defer {
            first.cleanup()
            second.cleanup()
        }

        #expect(first.suiteName != second.suiteName)
        #expect(first.sandboxID != second.sandboxID)

        // Mutating one's store preferences stays inside its own suite.
        first.store.preferences.hasSeenFeatureTour = false
        #expect(second.store.preferences.hasSeenFeatureTour)

        let firstDefaults = try #require(UserDefaults(suiteName: first.suiteName))
        let secondDefaults = try #require(UserDefaults(suiteName: second.suiteName))
        #expect(firstDefaults != secondDefaults)
    }

    @Test func cleanupRemovesOnlyItsOwnSuiteAndIsIdempotent() async throws {
        let sandbox = FleetGuidedDemoSandbox()
        let other = FleetGuidedDemoSandbox()
        defer { other.cleanup() }
        let suiteName = sandbox.suiteName

        // Write a marker into the sandbox suite so removal is observable.
        sandbox.store.preferences.hasSeenFeatureTour = false

        sandbox.cleanup()
        // Reopening the suite yields a fresh empty domain, proving removal.
        let reopened = try #require(UserDefaults(suiteName: suiteName))
        #expect(reopened.persistentDomain(forName: suiteName)?.isEmpty != false)

        // Other sandboxes still have their state.
        #expect(other.store.preferences.hasSeenFeatureTour)
        #expect(UserDefaults(suiteName: other.suiteName) != nil)

        // Idempotent: second cleanup does nothing and does not crash.
        sandbox.cleanup()
        sandbox.cleanup()
    }

    @Test func denyAllSessionBlocksRequestsAndCountsThemPerSandbox() async throws {
        let sandbox = FleetGuidedDemoSandbox()
        let other = FleetGuidedDemoSandbox()
        defer {
            sandbox.cleanup()
            other.cleanup()
        }

        #expect(sandbox.blockedRequestCount == 0)
        #expect(other.blockedRequestCount == 0)

        let url = try #require(URL(string: "https://public-pool.example/stats"))
        await #expect(throws: (any Error).self) {
            _ = try await sandbox.session.data(from: url)
        }
        #expect(sandbox.blockedRequestCount == 1)
        #expect(other.blockedRequestCount == 0)

        await #expect(throws: (any Error).self) {
            _ = try await other.session.data(from: url)
        }
        #expect(sandbox.blockedRequestCount == 1)
        #expect(other.blockedRequestCount == 1)
    }

    @Test func sandboxStateSurvivesAccidentalStoreRefreshWithoutNetwork() async {
        let sandbox = FleetGuidedDemoSandbox()
        defer { sandbox.cleanup() }

        // Demo-guarded refresh is a no-op; counters confirm nothing even attempted a request.
        await sandbox.store.refresh()
        #expect(sandbox.store.isDemo)
        #expect(sandbox.blockedRequestCount == 0)

        await sandbox.prepare()
        #expect(sandbox.blockedRequestCount == 0)
    }
}
