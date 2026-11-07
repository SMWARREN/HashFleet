import Foundation

/// Frequent readings of saved miners only. Discovery is deliberately not part of this loop.
public enum WatchFleetPolling {
    public static let interval: Duration = .seconds(10)

    /// The caller owns the active-scene task. A pass finishes before its 10-second wait starts.
    @MainActor
    public static func run(store: WatchFleetStore) async {
        guard !store.isDemo else { return }
        await run(refresh: { await store.refresh() }, sleep: { try await Task.sleep(for: interval) })
    }

    @MainActor
    static func run(
        refresh: @MainActor () async -> Void,
        sleep: @MainActor () async throws -> Void
    ) async {
        while !Task.isCancelled {
            await refresh()
            guard !Task.isCancelled else { return }
            do {
                try await sleep()
            } catch {
                return
            }
        }
    }
}

/// App-owned work, independent of a SwiftUI view task or navigation destination. A Watch can be inactive
/// while still frontmost, including wrist-down and transient overlays. Only actual background entry stops
/// work. No background runtime entitlement or indefinite background networking is requested.
@MainActor
public final class WatchFleetActivity {
    public enum Phase: Sendable { case active, inactive, background }

    public private(set) var isPolling = false
    private var phase: Phase = .background
    private weak var pollingStore: WatchFleetStore?
    private var pollingTask: Task<Void, Never>?

    public init() {}

    public func update(phase: Phase, store: WatchFleetStore?, discovery: WatchMinerDiscoveryController) {
        let previousPhase = self.phase
        self.phase = phase
        guard let store, !store.isDemo else {
            discovery.cancel()
            stopPolling()
            return
        }
        switch phase {
        case .background:
            discovery.suspendForBackground(store: store)
            stopPolling()
        case .inactive:
            // Do not cancel work merely because the screen dims or a view receives onDisappear.
            break
        case .active:
            discovery.startAutomaticallyIfNeeded(store: store)
            if !isPolling || pollingStore !== store || previousPhase != .active {
                restartPolling(store: store)
            }
        }
    }

    /// Read newly imported/manual entries promptly without making the loop's lifetime depend on miner count.
    public func inventoryDidChange(store: WatchFleetStore?) {
        guard isPolling, phase != .background, let store, !store.isDemo else { return }
        restartPolling(store: store)
    }

    private func restartPolling(store: WatchFleetStore) {
        let previous = pollingTask
        previous?.cancel()
        pollingStore = store
        isPolling = true
        pollingTask = Task {
            // A fast return must not join the old cancelled HTTP pass and then sleep for ten seconds.
            await previous?.value
            guard !Task.isCancelled else { return }
            await WatchFleetPolling.run(store: store)
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        isPolling = false
        pollingStore = nil
    }

    /// Deterministic cancellation seam for unit tests. Production ownership is the app's scene lifecycle.
    func waitForStoppedPolling() async { await pollingTask?.value }
}
