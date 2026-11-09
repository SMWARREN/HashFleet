import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

@MainActor
struct MinerWriteConfirmationTests {
    @Test func hardwareControlGateFollowsDemoState() {
        let gate = FleetHardwareControlGate()
        #expect(gate.isBlocked)
        let suite = "gate-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FleetStore(defaults: defaults, hardwareControlGate: gate)
        #expect(!gate.isBlocked)
        store.loadDemo()
        #expect(gate.isBlocked)
        store.clearDemo()
        #expect(!gate.isBlocked)
    }

    @Test func reviewedRequestClassificationKeepsHardwareChangesExplicit() {
        let device = MinerDevice(name: "Confirmation fixture", address: "fixture.test")
        let safe = PendingMinerWrite(
            endpoint: .settings,
            body: Data(#"{"hostname":"office"}"#.utf8),
            query: [],
            filename: nil
        )
        let tuning = PendingMinerWrite(
            endpoint: .settings,
            body: Data(#"{"frequency":500,"coreVoltage":1100}"#.utf8),
            query: [],
            filename: nil
        )
        #expect(!safe.highRisk)
        #expect(tuning.highRisk)
        #expect(MinerRequestSafety.coreVoltage(in: tuning.body) == 1100)
        _ = MinerWriteConfirmation(device: device, request: tuning, isDemo: false, onConfirm: {})
    }

    @Test func rawAndPoolRequestsRemainReviewedOrDestructive() {
        let raw = PendingMinerWrite(
            endpoint: .settings,
            body: Data(#"{"coreVoltage":1200}"#.utf8),
            query: [],
            filename: nil
        )
        let pool = PendingMinerWrite(
            endpoint: .updatePool(3),
            body: Data(#"{"stratumURL":"pool.example"}"#.utf8),
            query: [],
            filename: nil
        )
        let restart = PendingMinerWrite(endpoint: .restart, body: nil, query: [], filename: nil)
        #expect(raw.highRisk)
        #expect(pool.endpoint.isDestructive)
        #expect(restart.endpoint.isDestructive)
    }
}
