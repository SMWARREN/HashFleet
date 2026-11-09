import Foundation
import Observation
import SwiftUI
import HashFleetCore

#if !HASHFLEET_DIAGNOSTIC_CHECKS
import Testing
@testable import HashFleet
#endif

/// Executes the actual card body's reads against the real store. No view model or
/// Observation implementation is substituted. Call before starting any monitoring.
@MainActor
enum FleetMinerCardObservationChecks {
    private final class Signal: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func fire() { lock.lock(); value = true; lock.unlock() }
        var fired: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    static func run(store: FleetStore, insights: MiningInsightsStore) -> [String: Bool] {
        precondition(store.defaults !== UserDefaults.standard)
        precondition(store.liveTasks.isEmpty && store.refreshTask == nil)
        let first = MinerDevice(name: "Observation First", address: "first.invalid")
        let second = MinerDevice(name: "Observation Second", address: "second.invalid")
        store.devices = [first, second]
        func reading(_ rate: Double) -> MinerSnapshot {
            MinerSnapshot(info: MinerInfo(raw: ["hashRate": .number(rate), "power": .number(rate / 20)]))
        }
        store.snapshots = [first.id: reading(1_000), second.id: reading(2_000)]
        let firstCard = FleetObservedMinerOverviewCard(store: store, insights: insights, device: first, compact: false)
        let secondCard = FleetObservedMinerOverviewCard(store: store, insights: insights, device: second, compact: true)
        var results: [String: Bool] = [:]

        let firstSignal = Signal(), secondSignal = Signal(), wholeFleetSignal = Signal()
        withObservationTracking { _ = firstCard.body } onChange: { firstSignal.fire() }
        withObservationTracking { _ = secondCard.body } onChange: { secondSignal.fire() }
        withObservationTracking { _ = store.snapshots } onChange: { wholeFleetSignal.fire() }
        store.snapshots[second.id] = reading(75_000)
        results["unrelated_card_does_not_observe_other_snapshot"] = !firstSignal.fired
        results["changed_card_observes_own_snapshot"] = secondSignal.fired
        results["fleet_aggregate_still_observes_changes"] = wholeFleetSignal.fired
        results["shared_authority_matches_card_cell"] = store.snapshot(for: second.id) == store.snapshots[second.id]

        let ownSignal = Signal()
        withObservationTracking { _ = firstCard.body } onChange: { ownSignal.fire() }
        store.snapshots[first.id] = reading(99_000)
        results["first_card_observes_own_snapshot"] = ownSignal.fired

        let equalSignal = Signal()
        withObservationTracking { _ = firstCard.body } onChange: { equalSignal.fire() }
        let unchanged = store.snapshots[first.id]
        store.snapshots[first.id] = unchanged
        results["equal_snapshot_does_not_invalidate_card"] = !equalSignal.fired

        let missing = MinerDevice(name: "Observation Missing", address: "missing.invalid")
        store.devices.append(missing)
        let missingCard = FleetObservedMinerOverviewCard(store: store, insights: insights, device: missing, compact: false)
        let missingSignal = Signal()
        withObservationTracking { _ = missingCard.body } onChange: { missingSignal.fire() }
        store.snapshots[missing.id] = reading(3_000)
        results["initially_missing_snapshot_becomes_visible"] = missingSignal.fired

        let removeSignal = Signal()
        withObservationTracking { _ = secondCard.body } onChange: { removeSignal.fire() }
        store.devices.removeAll { $0.id == second.id }
        store.snapshots.removeValue(forKey: second.id)
        results["removal_invalidates_old_card"] = removeSignal.fired && store.snapshot(for: second.id) == nil

        let replacementSignal = Signal()
        withObservationTracking { _ = firstCard.body } onChange: { replacementSignal.fire() }
        store.snapshots = [:]
        results["bulk_reset_clears_visible_card"] = replacementSignal.fired && store.snapshot(for: first.id) == nil

        let errorSignal = Signal()
        withObservationTracking { _ = firstCard.body } onChange: { errorSignal.fire() }
        store.liveConnectionErrors[first.id] = "Synthetic live connection failure"
        results["connection_error_remains_observed"] = errorSignal.fired
        return results
    }
}

#if !HASHFLEET_DIAGNOSTIC_CHECKS
@Suite(.serialized) @MainActor
struct FleetMinerCardObservationTests {
    @Test func actualCardReadsOnlyItsMinerSnapshot() throws {
        let suite = "app.hashfleet.ui-tests.observation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let store = FleetStore(defaults: defaults, session: session)
        store.preferences.externalDataEnabled = false
        let insights = MiningInsightsStore(session: session)
        for (name, passed) in FleetMinerCardObservationChecks.run(store: store, insights: insights) {
            #expect(passed, "Observation boundary: \(name)")
        }
    }
}
#endif
