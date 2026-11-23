import Foundation
import Testing
import HashFleetCore
@testable import HashFleetMac

@Suite("Coverage Batch B", .serialized)
@MainActor
struct CoverageBatchBEvaluationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func device(_ name: String, _ address: String = "192.168.1.10",
                        kind: MinerDevice.Kind = .espMiner, credential: String? = nil) -> MinerDevice {
        MinerDevice(name: name, address: address, kind: kind, keychainCredentialReference: credential)
    }

    private func snapshot(mac: String? = "AA:BB:CC:DD:EE:01", at date: Date? = nil,
                          cached: Bool = false, reconnecting: Bool = false, error: String? = nil) -> MinerSnapshot {
        var raw: [String: JSONValue] = ["hostname": .string("rig")]
        if let mac { raw["macAddr"] = .string(mac) }
        return MinerSnapshot(
            info: MinerInfo(raw: raw), error: error, updatedAt: date ?? now,
            completeSnapshotAt: date ?? now, powerObservedAt: date ?? now,
            history: [], isCached: cached, isReconnecting: reconnecting
        )
    }

    @Test func targetsRequireCompleteFreshCredentialFreeFleets() {
        var prep = FleetWidgetRefreshPreparation()
        let rig = device("Rig")
        // First observation pins at `now`, a snapshot taken at `now` qualifies.
        let targets = prep.targets(devices: [rig], snapshots: [rig.id: snapshot()], isDemo: false, now: now)
        #expect(targets?.count == 1)
        #expect(targets?.first?.expectedMAC == FleetScheduledCheckTarget.normalizedMAC("AA:BB:CC:DD:EE:01"))

        // Demo, empty, oversized and duplicate fleets never produce targets.
        #expect(prep.targets(devices: [rig], snapshots: [rig.id: snapshot()], isDemo: true, now: now) == nil)
        #expect(prep.targets(devices: [], snapshots: [:], isDemo: false, now: now) == nil)
        let many = (0..<17).map { device("R\($0)", "192.168.1.\($0 + 20)") }
        #expect(prep.targets(devices: many, snapshots: [:], isDemo: false, now: now) == nil)
        #expect(prep.targets(devices: [rig, rig], snapshots: [rig.id: snapshot()], isDemo: false, now: now) == nil)
    }

    @Test func targetsRejectUnsafeOrStaleReadings() {
        let rig = device("Rig")
        let cases: [(String, [UUID: MinerSnapshot])] = [
            ("missing", [:]),
            ("cached", [rig.id: snapshot(cached: true)]),
            ("reconnecting", [rig.id: snapshot(reconnecting: true)]),
            ("error", [rig.id: snapshot(error: "down")]),
            ("no mac", [rig.id: snapshot(mac: nil)]),
            ("bad mac", [rig.id: snapshot(mac: "not-a-mac")]),
            ("stale", [rig.id: snapshot(at: now.addingTimeInterval(-3600))]),
            ("future", [rig.id: snapshot(at: now.addingTimeInterval(3600))])
        ]
        for (label, snapshots) in cases {
            var prep = FleetWidgetRefreshPreparation()
            #expect(prep.targets(devices: [rig], snapshots: snapshots, isDemo: false, now: now) == nil, Comment(rawValue: label))
        }
        for odd in [device("X", kind: .xmrig), device("C", credential: "keychain-ref"), device("Bad", "bad host")] {
            var prep = FleetWidgetRefreshPreparation()
            #expect(prep.targets(devices: [odd], snapshots: [odd.id: snapshot()], isDemo: false, now: now) == nil)
        }
    }

    @Test func addressChangeAndModeRoundTripResetObservationClock() {
        var prep = FleetWidgetRefreshPreparation()
        var rig = device("Rig")
        let old = snapshot(at: now)
        #expect(prep.targets(devices: [rig], snapshots: [rig.id: old], isDemo: false, now: now)?.count == 1)
        // Moving the address means the earlier snapshot cannot pin the new endpoint.
        rig.address = "192.168.1.99"
        let later = now.addingTimeInterval(10)
        #expect(prep.targets(devices: [rig], snapshots: [rig.id: old], isDemo: false, now: later) == nil)
        #expect(prep.targets(devices: [rig], snapshots: [rig.id: snapshot(at: later)], isDemo: false, now: later)?.count == 1)
        // Real -> demo -> real forgets earlier readings too.
        _ = prep.targets(devices: [rig], snapshots: [:], isDemo: true, now: later)
        let after = later.addingTimeInterval(5)
        #expect(prep.targets(devices: [rig], snapshots: [rig.id: snapshot(at: later)], isDemo: false, now: after) == nil)
        // Removed devices are dropped from bookkeeping.
        _ = prep.targets(devices: [], snapshots: [:], isDemo: false, now: after)
    }

    @Test func matchesPreparedFleetAgainstConfiguration() throws {
        var prep = FleetWidgetRefreshPreparation()
        let rig = device("Rig")
        let target = try #require(prep.targets(devices: [rig], snapshots: [rig.id: snapshot()], isDemo: false, now: now)?.first)
        let config = FleetWidgetRefreshConfiguration(
            version: 1, generation: UUID(), createdAt: now.addingTimeInterval(-60), renewedAt: now,
            expiresAt: now.addingTimeInterval(3600), targets: [target], automaticRefreshGeneration: nil
        )
        #expect(config.isValid)
        let fresh = [rig.id: snapshot(at: now)]
        #expect(FleetWidgetRefreshPreparation.matchesPreparedFleet(config, devices: [rig], snapshots: fresh, now: now))
        // No in-memory reading is not a revocation.
        #expect(FleetWidgetRefreshPreparation.matchesPreparedFleet(config, devices: [rig], snapshots: [:], now: now))
        // A different MAC contradicts the pin.
        #expect(!FleetWidgetRefreshPreparation.matchesPreparedFleet(
            config, devices: [rig], snapshots: [rig.id: snapshot(mac: "AA:BB:CC:DD:EE:99", at: now)], now: now))
        #expect(!FleetWidgetRefreshPreparation.matchesPreparedFleet(
            config, devices: [rig], snapshots: [rig.id: snapshot(mac: nil, at: now)], now: now))
        // Cached, reconnecting and errored frames cannot contradict.
        for frame in [snapshot(mac: "AA:BB:CC:DD:EE:99", cached: true), snapshot(mac: "AA:BB:CC:DD:EE:99", reconnecting: true),
                      snapshot(mac: "AA:BB:CC:DD:EE:99", error: "x")] {
            #expect(FleetWidgetRefreshPreparation.matchesPreparedFleet(config, devices: [rig], snapshots: [rig.id: frame], now: now))
        }
        // Structural mismatches.
        var moved = rig
        moved.address = "192.168.1.200"
        #expect(!FleetWidgetRefreshPreparation.matchesPreparedFleet(config, devices: [moved], snapshots: [:], now: now))
        #expect(!FleetWidgetRefreshPreparation.matchesPreparedFleet(config, devices: [], snapshots: [:], now: now))
        #expect(!FleetWidgetRefreshPreparation.matchesPreparedFleet(config, devices: [device("Other")], snapshots: [:], now: now))
        #expect(!FleetWidgetRefreshPreparation.matchesPreparedFleet(config, devices: [device("X", kind: .xmrig)], snapshots: [:], now: now))
        #expect(!FleetWidgetRefreshPreparation.matchesPreparedFleet(config, devices: [rig], snapshots: [:], now: Date(timeIntervalSince1970: .infinity)))
    }
}
