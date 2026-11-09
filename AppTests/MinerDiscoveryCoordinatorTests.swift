import Foundation
import Testing
@testable import HashFleet

/// Exercises the coordinator's progressive-scanning behaviour with a fake runner. No real
/// network traffic ever happens here; the runner reports batches synchronously through the
/// progress callback the way MinerDiscoveryService does per 32-host batch.
@Suite("Miner discovery coordinator")
@MainActor
struct MinerDiscoveryCoordinatorTests {
    private let plan = MinerDiscoveryScanPlan.plan(forIPv4Address: "192.168.1.5")!

    @Test func foundMinersAppearProgressivelyWhileScanningContinues() async throws {
        let gate = Gate()
        let coordinator = MinerDiscoveryCoordinator(
            planProvider: { [plan] in plan },
            runner: { _, progress in
                progress([MinerDiscoveryCandidate(address: "192.168.1.20", name: "B", model: nil)], 32)
                await gate.wait()
                progress([MinerDiscoveryCandidate(address: "192.168.1.9", name: "A", model: nil)], 253)
                return [
                    MinerDiscoveryCandidate(address: "192.168.1.20", name: "B", model: nil),
                    MinerDiscoveryCandidate(address: "192.168.1.9", name: "A", model: nil)
                ]
            }
        )
        coordinator.start()

        // The first batch must be visible before the scan has swept the whole /24.
        try await waitFor { coordinator.candidates.map(\.address) == ["192.168.1.20"] }
        #expect(coordinator.isScanning)
        #expect(coordinator.probedHosts == 32)

        gate.open()
        try await waitFor { !coordinator.isScanning }
        #expect(coordinator.state == .results)
        // Final ordering is numeric by address, not the order batches happened to finish in.
        #expect(coordinator.candidates.map(\.address) == ["192.168.1.9", "192.168.1.20"])
        #expect(coordinator.probedHosts == plan.hosts.count)
    }

    @Test func cancellingKeepsMinersThatWereAlreadyFound() async throws {
        let gate = Gate()
        let coordinator = MinerDiscoveryCoordinator(
            planProvider: { [plan] in plan },
            runner: { _, progress in
                progress([MinerDiscoveryCandidate(address: "192.168.1.12", name: "Desk", model: nil)], 32)
                await gate.wait()
                return [MinerDiscoveryCandidate(address: "192.168.1.12", name: "Desk", model: nil)]
            }
        )
        coordinator.start()
        try await waitFor { coordinator.candidates.count == 1 }

        coordinator.cancel()
        #expect(!coordinator.isScanning)
        #expect(coordinator.state == .results)
        #expect(coordinator.candidates.map(\.address) == ["192.168.1.12"])
        gate.open()
    }

    @Test func cancellingBeforeAnythingIsFoundReturnsToIdle() async {
        let gate = Gate()
        let coordinator = MinerDiscoveryCoordinator(
            planProvider: { [plan] in plan },
            runner: { _, _ in
                await gate.wait()
                return []
            }
        )
        coordinator.start()
        #expect(coordinator.isScanning)
        coordinator.cancel()
        #expect(coordinator.state == .idle)
        #expect(coordinator.candidates.isEmpty)
        gate.open()
    }

    @Test func missingLocalNetworkSurfacesAnUnavailableState() async {
        let coordinator = MinerDiscoveryCoordinator(
            planProvider: { nil },
            runner: { _, _ in [] }
        )
        coordinator.start()
        guard case .unavailable(let message) = coordinator.state else {
            Issue.record("Expected .unavailable, got \(coordinator.state)")
            return
        }
        #expect(message.contains("Wi-Fi"))
        #expect(coordinator.candidates.isEmpty)
    }

    @Test func runnerFailureSurfacesACalmUnavailableState() async throws {
        struct ScanFailed: Error {}
        let coordinator = MinerDiscoveryCoordinator(
            planProvider: { [plan] in plan },
            runner: { _, _ in throw ScanFailed() }
        )
        coordinator.start()
        try await waitFor {
            if case .unavailable = coordinator.state { return true }
            return false
        }
        #expect(coordinator.candidates.isEmpty)
    }

    // MARK: - Helpers

    private func waitFor(_ condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            if ContinuousClock.now > deadline {
                Issue.record("Timed out waiting for coordinator state")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// One-shot async gate so a fake runner can hold mid-scan while the test inspects the
/// coordinator, then finish on demand.
private final class Gate: @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false
    private let lock = NSLock()

    func open() {
        lock.lock()
        if let pending = continuation {
            continuation = nil
            lock.unlock()
            pending.resume()
        } else {
            opened = true
            lock.unlock()
        }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if opened {
                lock.unlock()
                continuation.resume()
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }
}
