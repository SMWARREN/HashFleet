import Foundation
import Observation

/// Owns one foreground discovery attempt. A current result or background checkpoint can append validated
/// miners. Explicit cancellation, demo mode and late callbacks never add entries. Readings refresh separately.
@MainActor
@Observable
public final class WatchMinerDiscoveryController {
    public private(set) var isScanning = false
    public private(set) var isPaused = false
    public private(set) var completedHosts = 0
    public private(set) var totalHosts = 0
    public private(set) var foundCount = 0
    public private(set) var addedCount: Int?
    public private(set) var message: String?
    public private(set) var isPartialSubnet = false
    public private(set) var reachedTimeLimit = false

    @ObservationIgnored private let discovery: any WatchMinerDiscovering
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var scanID: UUID?
    @ObservationIgnored private var attemptedAutomaticScan = false
    @ObservationIgnored private var initiallyKnown: Set<String> = []
    @ObservationIgnored private var latestDiscoveries: [WatchMiner] = []

    public init(discovery: any WatchMinerDiscovering = WatchLocalMinerDiscovery()) {
        self.discovery = discovery
    }

    /// An empty real fleet gets one attempt per app session. A background-interrupted search may retry on
    /// activation, but completed, failed or explicitly stopped attempts never repeat on every readings refresh.
    public func startAutomaticallyIfNeeded(store: WatchFleetStore) {
        if isPaused, !store.isDemo {
            start(store: store)
            return
        }
        guard !store.isDemo, !attemptedAutomaticScan else { return }
        attemptedAutomaticScan = true
        guard store.miners.isEmpty else { return }
        start(store: store)
    }

    /// Explicit retries are allowed, but never overlap another scan or run against a demo store.
    public func start(store: WatchFleetStore) {
        guard !store.isDemo, !isScanning else { return }
        attemptedAutomaticScan = true
        let id = UUID()
        let initiallyKnown = Set(store.miners.map { $0.address })
        self.initiallyKnown = initiallyKnown
        latestDiscoveries = []
        scanID = id
        isScanning = true
        isPaused = false
        completedHosts = 0
        totalHosts = 0
        foundCount = 0
        addedCount = nil
        message = nil
        isPartialSubnet = false
        reachedTimeLimit = false
        scanTask = Task { [weak self, discovery] in
            do {
                let result = try await discovery.scan { [weak self] progress in
                    await self?.receive(progress, scanID: id)
                }
                guard !Task.isCancelled else { return }
                self?.finish(result, store: store, initiallyKnown: initiallyKnown, scanID: id)
            } catch is CancellationError {
                self?.finishCancellation(scanID: id)
            } catch {
                self?.finishFailure(error, scanID: id)
            }
        }
    }

    /// Explicit Stop or demo entry. Unlike background suspension, this never schedules an automatic retry.
    public func cancel() {
        guard isScanning || isPaused else { return }
        scanID = nil
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        isPaused = false
        message = "Search stopped. Your saved miners are unchanged."
    }

    /// Only genuine background entry interrupts the scan. Save already validated discoveries before watchOS
    /// can suspend the process, and retry the bounded search on the next activation. Wrist-down inactivity
    /// must not call this: an inactive frontmost app is not necessarily in the background.
    public func suspendForBackground(store: WatchFleetStore) {
        guard isScanning, let id = scanID else { return }
        let task = scanTask
        finish(WatchDiscoveryResult(
            miners: latestDiscoveries, completedHosts: completedHosts, totalHosts: totalHosts,
            isPartialSubnet: isPartialSubnet, reachedTimeLimit: false
        ), store: store, initiallyKnown: initiallyKnown, scanID: id)
        task?.cancel()
        isPaused = true
        message = addedCount == nil && !latestDiscoveries.isEmpty
            ? "Search paused. New miners couldn't be saved. Reopen the app to retry."
            : "Search paused. Saved miners are kept. The search retries when you reopen the app."
    }

    /// A synchronization seam for deterministic unit tests, not a second scan or a polling loop.
    func waitForCurrentScan() async {
        await scanTask?.value
    }

    private func receive(_ progress: WatchDiscoveryProgress, scanID id: UUID) {
        guard scanID == id, isScanning, !Task.isCancelled else { return }
        totalHosts = max(0, min(254, progress.totalHosts))
        completedHosts = max(completedHosts, min(totalHosts, max(0, progress.completedHosts)))
        foundCount = Set(progress.miners.map { $0.address }).count
        latestDiscoveries = progress.miners
        isPartialSubnet = progress.isPartialSubnet
    }

    private func finish(_ result: WatchDiscoveryResult, store: WatchFleetStore, initiallyKnown: Set<String>, scanID id: UUID) {
        guard scanID == id, isScanning, !Task.isCancelled else { return }
        defer {
            isScanning = false
            scanTask = nil
            scanID = nil
        }
        totalHosts = max(0, min(254, result.totalHosts))
        completedHosts = min(totalHosts, max(0, result.completedHosts))
        isPartialSubnet = result.isPartialSubnet
        reachedTimeLimit = result.reachedTimeLimit
        var seen = Set<String>()
        let unique = result.miners.filter { seen.insert($0.address).inserted }
        foundCount = unique.count
        let known = Set(store.miners.map { $0.address })
        // Do not undo a removal made while this scan was running.
        let missing = unique.filter { !known.contains($0.address) && !initiallyKnown.contains($0.address) }
        let space = max(0, WatchFleetLimits.maximumMiners - store.miners.count)
        let additions = Array(missing.prefix(space))
        do {
            let added = try store.importMiners(additions)
            addedCount = added
            if missing.count > space {
                message = "Added \(added). This Watch holds up to \(WatchFleetLimits.maximumMiners) miners. Remove an entry to add more."
            } else if added > 0 {
                message = added == 1 ? "Added 1 miner. No address typing needed." : "Added \(added) miners. No address typing needed."
            } else if !unique.isEmpty {
                message = "Found \(unique.count) compatible miners. No new entries added."
            } else {
                message = "No compatible miners found. Check the Watch’s Wi-Fi and that your miners are reachable, then scan again."
            }
        } catch {
            addedCount = nil
            message = "Found miners, but this Watch couldn't save them. Your saved list is unchanged."
        }
    }

    private func finishCancellation(scanID id: UUID) {
        guard scanID == id else { return }
        isScanning = false
        scanTask = nil
        scanID = nil
        message = "Search stopped. Your saved miners are unchanged."
    }

    private func finishFailure(_ error: any Error, scanID id: UUID) {
        guard scanID == id else { return }
        isScanning = false
        scanTask = nil
        scanID = nil
        message = (error as? WatchDiscoveryError)?.errorDescription
            ?? "The search couldn't finish. Check the Watch’s Wi-Fi connection, then try again."
    }
}
