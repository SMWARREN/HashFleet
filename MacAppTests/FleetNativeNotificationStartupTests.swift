import Foundation
import Testing
@testable import HashFleetMac

@MainActor
private final class StartupAuthorizationProbe {
    private(set) var requestCount = 0
    private(set) var requestStarted = false
    private var continuation: CheckedContinuation<Bool, Never>?

    func request() async -> Bool {
        requestCount += 1
        requestStarted = true
        return await withCheckedContinuation { continuation = $0 }
    }

    func resolve(_ authorized: Bool = true) {
        continuation?.resume(returning: authorized)
        continuation = nil
    }
}

@Suite("Native startup notification authorization", .serialized)
struct FleetNativeNotificationStartupTests {
    @MainActor
    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "app.hashfleet.mac.notification-startup-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    @MainActor
    private func waitUntil(
        _ predicate: @MainActor () -> Bool,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        for _ in 0..<250 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("Timed out waiting for native startup state", sourceLocation: sourceLocation)
    }

    @MainActor
    @Test func enabledAlertsRequestAuthorizationBeforeFirstMonitoringRefresh() async {
        let (defaults, suite) = isolatedDefaults()
        let probe = StartupAuthorizationProbe()
        let runtime = FleetMacRuntime(
            defaults: defaults,
            isTesting: false,
            requestNotificationAuthorization: { await probe.request() }
        )
        defer {
            runtime.stop()
            probe.resolve()
            defaults.removePersistentDomain(forName: suite)
        }

        // Best-share alerts default on. An empty isolated fleet keeps this fixture offline.
        #expect(runtime.store.preferences.bestShareNotificationsEnabled)
        runtime.start()
        await waitUntil { probe.requestStarted }
        #expect(probe.requestCount == 1)
        #expect(runtime.store.lastRefresh == nil)
        #expect(!runtime.store.isRefreshing)

        probe.resolve(true)
        await waitUntil { runtime.store.lastRefresh != nil }
        #expect(runtime.store.lastRefresh != nil)
    }

    @MainActor
    @Test func allDisabledAlertsDoNotRequestAuthorization() async {
        let (defaults, suite) = isolatedDefaults()
        defaults.set(false, forKey: FleetPreferences.Keys.blockNotificationsEnabled)
        defaults.set(false, forKey: FleetPreferences.Keys.bestShareNotificationsEnabled)
        defaults.set(false, forKey: FleetPreferences.Keys.stateChangeNotificationsEnabled)
        defaults.set(false, forKey: FleetPreferences.Keys.metricAlertNotificationsEnabled)
        defaults.set(false, forKey: FleetPreferences.Keys.powerAlertNotificationsEnabled)
        let probe = StartupAuthorizationProbe()
        let runtime = FleetMacRuntime(
            defaults: defaults,
            isTesting: false,
            requestNotificationAuthorization: { await probe.request() }
        )
        defer {
            runtime.stop()
            probe.resolve()
            defaults.removePersistentDomain(forName: suite)
        }

        runtime.start()
        await waitUntil { runtime.store.lastRefresh != nil }
        #expect(probe.requestCount == 0)
    }

    @MainActor
    @Test func demoAndTestingStartupNeverRequestAuthorization() async {
        let (demoDefaults, demoSuite) = isolatedDefaults()
        let demoProbe = StartupAuthorizationProbe()
        let demoRuntime = FleetMacRuntime(
            defaults: demoDefaults,
            isTesting: false,
            requestNotificationAuthorization: { await demoProbe.request() }
        )
        demoRuntime.store.loadDemo()
        defer {
            demoRuntime.stop()
            demoProbe.resolve()
            demoDefaults.removePersistentDomain(forName: demoSuite)
        }
        demoRuntime.start()
        try? await Task.sleep(for: .milliseconds(30))
        #expect(demoRuntime.store.isDemo)
        #expect(demoProbe.requestCount == 0)

        let (testDefaults, testSuite) = isolatedDefaults()
        let testProbe = StartupAuthorizationProbe()
        let testRuntime = FleetMacRuntime(
            defaults: testDefaults,
            isTesting: true,
            requestNotificationAuthorization: { await testProbe.request() }
        )
        defer {
            testRuntime.stop()
            testProbe.resolve()
            testDefaults.removePersistentDomain(forName: testSuite)
        }
        testRuntime.start()
        try? await Task.sleep(for: .milliseconds(30))
        #expect(testRuntime.isTesting)
        #expect(testProbe.requestCount == 0)
    }

    @MainActor
    @Test func cancellingStartupWhilePermissionIsPendingDoesNotStartMonitoring() async {
        let (defaults, suite) = isolatedDefaults()
        let probe = StartupAuthorizationProbe()
        let runtime = FleetMacRuntime(
            defaults: defaults,
            isTesting: false,
            requestNotificationAuthorization: { await probe.request() }
        )
        defer {
            runtime.stop()
            probe.resolve()
            defaults.removePersistentDomain(forName: suite)
        }

        runtime.start()
        await waitUntil { probe.requestStarted }
        runtime.stop()
        probe.resolve(true)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(!runtime.isRunning)
        #expect(runtime.store.lastRefresh == nil)
        #expect(!runtime.store.isRefreshing)
    }
}
