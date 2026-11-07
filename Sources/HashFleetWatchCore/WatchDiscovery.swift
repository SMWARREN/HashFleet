import Foundation

/// A cumulative snapshot of a local discovery scan in progress.
///
/// `miners` is the full, de-duplicated, numerically sorted set of miners discovered so far, not an incremental
/// delta. Consumers may replace their list with it on every callback.
public struct WatchDiscoveryProgress: Sendable {
    /// Cumulative, unique, numerically sorted discoveries so far.
    public let miners: [WatchMiner]
    /// Number of candidate hosts that have finished (found or not) so far.
    public let completedHosts: Int
    /// Number of candidate hosts the scan planned to probe.
    public let totalHosts: Int
    /// True when the LAN is wider than a `/24`, so only the Watch's own `/24` was scanned.
    public let isPartialSubnet: Bool

    public init(miners: [WatchMiner], completedHosts: Int, totalHosts: Int, isPartialSubnet: Bool) {
        self.miners = miners
        self.completedHosts = completedHosts
        self.totalHosts = totalHosts
        self.isPartialSubnet = isPartialSubnet
    }
}

/// The final outcome of a local discovery scan.
public struct WatchDiscoveryResult: Sendable {
    /// Cumulative, unique, numerically sorted discoveries.
    public let miners: [WatchMiner]
    /// Number of candidate hosts that finished.
    public let completedHosts: Int
    /// Number of candidate hosts the scan planned to probe.
    public let totalHosts: Int
    /// True when only the Watch's own `/24` of a wider LAN was scanned.
    public let isPartialSubnet: Bool
    /// True when the scan stopped launching probes because the overall time budget was reached.
    public let reachedTimeLimit: Bool

    public init(
        miners: [WatchMiner],
        completedHosts: Int,
        totalHosts: Int,
        isPartialSubnet: Bool,
        reachedTimeLimit: Bool
    ) {
        self.miners = miners
        self.completedHosts = completedHosts
        self.totalHosts = totalHosts
        self.isPartialSubnet = isPartialSubnet
        self.reachedTimeLimit = reachedTimeLimit
    }
}

/// Finds miners on the local network without the user typing an address.
public protocol WatchMinerDiscovering: Sendable {
    /// Scans the local subnet, reporting cumulative progress, and returns the final result.
    ///
    /// Throws `CancellationError` promptly if the calling task is cancelled, and `WatchDiscoveryError` when the
    /// Watch has no usable direct Wi-Fi link or the derived plan is unsafe.
    func scan(
        onProgress: @escaping @Sendable (WatchDiscoveryProgress) async -> Void
    ) async throws -> WatchDiscoveryResult
}

/// Why discovery could not run. Messages are generic and never include raw system errors, response bodies,
/// addresses or secrets.
public enum WatchDiscoveryError: Error, LocalizedError, Sendable, Equatable {
    /// The Watch is not on a direct Wi-Fi network (for example it only has a companion/cellular route).
    case noLocalWiFi
    /// A subnet was found but it is not a safe, private, scannable plan.
    case invalidPlan
    /// Discovery could not complete for an unexpected reason.
    case failed

    public var errorDescription: String? {
        switch self {
        case .noLocalWiFi:
            "Connect the Watch to the same Wi-Fi network as your miners to find them automatically."
        case .invalidPlan:
            "This network can't be scanned automatically. Add a miner by its address instead."
        case .failed:
            "Couldn't search the network. Try again."
        }
    }
}
