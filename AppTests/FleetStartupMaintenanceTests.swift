import Foundation
import Testing
#if os(macOS)
@testable import HashFleetMac
#else
@testable import HashFleet
#endif

@Suite(.serialized) @MainActor
struct FleetStartupMaintenanceTests {
    @Test func failedCleanupDoesNotConsumeFlagAndRetries() async {
        let fixture = MaintenanceFixture()
        defer { fixture.finish() }
        fixture.failures = [.phantomBlocks]
        await fixture.helper.runNow()
        #expect(!fixture.defaults.bool(forKey: FleetStartupMaintenance.Cleanup.phantomBlocks.completionKey!))
        #expect(fixture.defaults.bool(forKey: FleetStartupMaintenance.Cleanup.bestShareV1.completionKey!))
        fixture.failures = []
        let previousCalls = fixture.calls.count
        await fixture.helper.runNow()
        #expect(Array(fixture.calls.dropFirst(previousCalls)) == [.phantomBlocks, .pollingDuplicates])
        #expect(fixture.defaults.bool(forKey: FleetStartupMaintenance.Cleanup.phantomBlocks.completionKey!))
    }

    @Test func successfulNoOpCleanupMarksOnlyItsInjectedPreferenceSuite() async {
        let fixture = MaintenanceFixture()
        let other = MaintenanceFixture()
        defer { fixture.finish(); other.finish() }
        await fixture.helper.runNow()
        for cleanup in FleetStartupMaintenance.Cleanup.allCases {
            guard let key = cleanup.completionKey else { continue }
            #expect(fixture.defaults.bool(forKey: key))
            #expect(!other.defaults.bool(forKey: key))
        }
        #expect(fixture.calls == FleetStartupMaintenance.Cleanup.allCases)
        fixture.calls = []
        await fixture.helper.runNow()
        #expect(fixture.calls == [.pollingDuplicates])
    }

    @Test func demoNeverStartsCleanupOrConsumesFlags() async {
        let fixture = MaintenanceFixture()
        defer { fixture.finish() }
        fixture.isDemo = true
        #expect(fixture.helper.run() == nil)
        await fixture.helper.runNow()
        #expect(fixture.calls.isEmpty)
        #expect(fixture.defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("app.hashfleet.") }.isEmpty)
    }

    @Test func demoEnteredBeforeScheduledTaskExecutesBlocksCleanup() async {
        let fixture = MaintenanceFixture()
        defer { fixture.finish() }
        let scheduled = fixture.helper.run()
        fixture.isDemo = true
        await scheduled?.value
        #expect(fixture.calls.isEmpty)
    }

    @Test func demoEnteredDuringCleanupStopsLaterWorkAndFlagConsumption() async {
        let fixture = MaintenanceFixture()
        defer { fixture.finish() }
        let pause = MaintenancePause()
        fixture.pause = pause
        let running = Task { await fixture.helper.runNow() }
        await pause.waitUntilEntered()
        fixture.isDemo = true
        pause.resume()
        await running.value
        #expect(fixture.calls == [.phantomBlocks])
        #expect(!fixture.defaults.bool(forKey: FleetStartupMaintenance.Cleanup.phantomBlocks.completionKey!))
    }

    @Test func overlappingRunsDoNotDuplicatePendingCleanup() async {
        let fixture = MaintenanceFixture()
        defer { fixture.finish() }
        let pause = MaintenancePause()
        fixture.pause = pause
        let running = Task { await fixture.helper.runNow() }
        await pause.waitUntilEntered()
        await fixture.helper.runNow()
        #expect(fixture.calls == [.phantomBlocks])
        pause.resume()
        await running.value
        #expect(fixture.calls == FleetStartupMaintenance.Cleanup.allCases)
    }

    @Test func cancellationKeepsCleanupRetryable() async {
        let fixture = MaintenanceFixture()
        defer { fixture.finish() }
        let pause = MaintenancePause()
        fixture.pause = pause
        let running = Task { await fixture.helper.runNow() }
        await pause.waitUntilEntered()
        running.cancel()
        pause.resume()
        await running.value
        #expect(fixture.calls == [.phantomBlocks])
        #expect(!fixture.defaults.bool(forKey: FleetStartupMaintenance.Cleanup.phantomBlocks.completionKey!))
        fixture.calls = []
        await fixture.helper.runNow()
        #expect(fixture.calls == FleetStartupMaintenance.Cleanup.allCases)
    }

    @Test func emptyFleetDoesNotConsumeOrphanCleanupFlag() async {
        let fixture = MaintenanceFixture()
        defer { fixture.finish() }
        fixture.minerIds = []
        await fixture.helper.runNow()
        let key = FleetStartupMaintenance.Cleanup.orphanedAchievements.completionKey!
        #expect(!fixture.calls.contains(.orphanedAchievements))
        #expect(!fixture.defaults.bool(forKey: key))
        fixture.minerIds = ["new-fixture-id"]
        fixture.calls = []
        await fixture.helper.runNow()
        #expect(fixture.calls == [.orphanedAchievements, .pollingDuplicates])
        #expect(fixture.defaults.bool(forKey: key))
    }
}

@MainActor
private final class MaintenanceFixture {
    let suite = "app.hashfleet.audit-fixes.maintenance." + UUID().uuidString
    let defaults: UserDefaults
    var isDemo = false
    var minerIds: Set<String> = ["fixture-id"]
    var failures: Set<FleetStartupMaintenance.Cleanup> = []
    var calls: [FleetStartupMaintenance.Cleanup] = []
    var pause: MaintenancePause?

    init() { defaults = UserDefaults(suiteName: suite)! }

    var helper: FleetStartupMaintenance {
        FleetStartupMaintenance(
            defaults: defaults, isDemo: { self.isDemo }, currentMinerIds: { self.minerIds },
            perform: { cleanup, ids in
                #expect(ids == self.minerIds)
                self.calls.append(cleanup)
                if let pause = self.pause {
                    self.pause = nil
                    await pause.enter()
                }
                if self.failures.contains(cleanup) { throw MaintenanceFailure.injected }
            }
        )
    }

    func finish() { defaults.removePersistentDomain(forName: suite) }
}

private enum MaintenanceFailure: Error { case injected }

@MainActor
private final class MaintenancePause {
    private var entered = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var continuation: CheckedContinuation<Void, Never>?

    func enter() async {
        entered = true
        startWaiter?.resume()
        startWaiter = nil
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
