import Foundation
import Testing
@testable import HashFleetMac

@Suite("Discovery session isolation")
@MainActor
struct MinerDiscoverySessionTests {
    @Test func oldProgressCannotLeakIntoANewScan() async throws {
        let runs = ControlledScans()
        let plan = MinerDiscoveryScanPlan.plan(forIPv4Address: "192.168.1.5")!
        let coordinator = MinerDiscoveryCoordinator(
            planProvider: { plan },
            runner: { _, progress in await runs.run(progress) }
        )
        defer { runs.finishAll() }
        coordinator.start()
        try await waitFor { runs.callbacks.count == 1 }
        coordinator.cancel()
        coordinator.start()
        try await waitFor { runs.callbacks.count == 2 }
        let old = MinerDiscoveryCandidate(address: "192.168.1.10", name: "Old", model: nil)
        runs.callbacks[0]([old], 32)
        // The old callback deliberately ignores cancellation to simulate queued delivery.
        for _ in 0..<10 { await Task.yield() }
        #expect(coordinator.candidates.isEmpty)
        #expect(coordinator.probedHosts == 0)
        let current = MinerDiscoveryCandidate(address: "192.168.1.11", name: "Current", model: nil)
        runs.callbacks[1]([current], 32)
        try await waitFor { coordinator.candidates == [current] }
        coordinator.cancel()
    }

    @Test func networkFailureDoesNotBecomeNoResults() async throws {
        let plan = MinerDiscoveryScanPlan.plan(forIPv4Address: "192.168.1.5")!
        let coordinator = MinerDiscoveryCoordinator(
            planProvider: { plan },
            runner: { _, _ in throw MinerDiscoveryService.ScanError.networkUnavailable }
        )
        coordinator.start()
        try await waitFor { !coordinator.isScanning }
        guard case .unavailable(let message) = coordinator.state else {
            Issue.record("Network failure incorrectly reported as \(coordinator.state)")
            return
        }
        #expect(message.contains("Local Network"))
    }

    private func waitFor(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for discovery state")
    }
}

@MainActor
private final class ControlledScans {
    var callbacks: [MinerDiscoveryCoordinator.ScanProgress] = []
    private var continuations: [CheckedContinuation<[MinerDiscoveryCandidate], Never>] = []

    func run(_ progress: @escaping MinerDiscoveryCoordinator.ScanProgress) async -> [MinerDiscoveryCandidate] {
        callbacks.append(progress)
        return await withCheckedContinuation { continuations.append($0) }
    }

    func finishAll() {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume(returning: []) }
    }
}
