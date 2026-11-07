import Foundation
import SwiftUI
import HashFleetCore

/// Pure presentation decisions shared by the dashboard fleet list and its cards.
///
/// Keeping these strings and state rules outside SwiftUI makes the calm, informative states
/// testable without snapshots while leaving the source of truth in FleetStore.
enum FleetMinerPresentationState: Equatable, Sendable {
    case sample
    case loading
    case live
    case online
    case stale
    case unreachable
    case connecting
    case reconnecting

    static func resolve(
        isDemo: Bool,
        hasInfo: Bool,
        hasError: Bool,
        isLive: Bool,
        isReconnecting: Bool = false
    ) -> Self {
        if isDemo { return .sample }
        if isReconnecting { return .reconnecting }
        if hasError { return hasInfo ? .stale : .unreachable }
        if isLive { return .live }
        if hasInfo { return .online }
        return .connecting
    }

    var title: String {
        switch self {
        case .sample: "Sample"
        case .loading, .connecting: "Connecting"
        case .reconnecting: "Reconnecting…"
        case .live: "Live"
        case .online: "Online"
        case .stale: "Unreachable"
        case .unreachable: "Unreachable"
        }
    }

    var isStale: Bool {
        self == .stale
    }

    var color: Color {
        switch self {
        case .sample:
            FleetTheme.accent
        case .live, .online:
            FleetTheme.positive
        case .stale, .unreachable:
            FleetTheme.warning
        case .loading, .connecting, .reconnecting:
            FleetTheme.secondary
        }
    }

    var isOperational: Bool {
        self == .live || self == .online
    }
}

struct FleetAttentionSummary: Equatable, Sendable {
    let unreachable: [MinerDevice]
    let liveFallbacks: [MinerDevice]

    init(
        devices: [MinerDevice],
        snapshots: [UUID: MinerSnapshot],
        liveConnectionErrors: [UUID: String]
    ) {
        var unreachable: [MinerDevice] = []
        var liveFallbacks: [MinerDevice] = []
        unreachable.reserveCapacity(devices.count)
        liveFallbacks.reserveCapacity(devices.count)

        for device in devices {
            let snapshot = snapshots[device.id]
            guard snapshot?.isReconnecting != true else { continue }
            if snapshot?.error != nil {
                unreachable.append(device)
            } else if liveConnectionErrors[device.id] != nil {
                liveFallbacks.append(device)
            }
        }

        self.unreachable = unreachable
        self.liveFallbacks = liveFallbacks
    }

    var count: Int { unreachable.count + liveFallbacks.count }
    var hasUnreachable: Bool { !unreachable.isEmpty }
    var needsAttention: Bool { count > 0 }
}

struct FleetHeroRefreshPresentation: Equatable, Sendable {
    struct Context: Equatable, Sendable {
        let isDemo: Bool
        let isInitialLoading: Bool
        let isRefreshing: Bool
        let realtimeMonitoring: Bool
        let liveConnectionCount: Int
        let liveFallbackCount: Int
    }

    let text: String
    let showsProgress: Bool
    let usesMonospacedCaption: Bool

    static func resolve(_ context: Context) -> Self {
        if context.isDemo {
            return Self(text: "SIMULATED", showsProgress: false, usesMonospacedCaption: true)
        }
        if context.isInitialLoading {
            return Self(text: "Checking miners…", showsProgress: true, usesMonospacedCaption: false)
        }
        if context.isRefreshing {
            return Self(text: "Refreshing…", showsProgress: true, usesMonospacedCaption: false)
        }
        if !context.realtimeMonitoring {
            return Self(text: "ON OPEN / PULL", showsProgress: false, usesMonospacedCaption: true)
        }
        if context.liveConnectionCount > 0 {
            return Self(text: "REALTIME", showsProgress: false, usesMonospacedCaption: true)
        }
        if context.liveFallbackCount > 0 {
            return Self(text: "HTTP FALLBACK", showsProgress: false, usesMonospacedCaption: true)
        }
        return Self(text: "CONNECTING LIVE", showsProgress: false, usesMonospacedCaption: true)
    }
}

struct FleetDashboardListSummary: Equatable, Sendable {
    let totalCount: Int
    let onlineCount: Int
    let attentionCount: Int
    let isRefreshing: Bool
    var reconnectingCount = 0

    private var safeTotalCount: Int { max(0, totalCount) }
    private var safeOnlineCount: Int { min(max(0, onlineCount), safeTotalCount) }
    private var safeAttentionCount: Int { max(0, attentionCount) }

    var subtitle: String {
        guard safeTotalCount > 0 else { return "Add a miner to start monitoring" }
        if reconnectingCount > 0 { return reconnectingLabel + "…" }

        let online = "\(safeOnlineCount) of \(safeTotalCount) online"
        if isRefreshing {
            return "Updating readings · \(online)"
        }
        if safeAttentionCount > 0 {
            let noun = safeAttentionCount == 1 ? "needs" : "need"
            return "\(online) · \(safeAttentionCount) \(noun) attention"
        }
        return online
    }

    var accessibilityLabel: String {
        guard safeTotalCount > 0 else { return "No miners added" }
        if reconnectingCount > 0 { return reconnectingLabel }

        let online = "\(safeOnlineCount) of \(safeTotalCount) online"
        if isRefreshing {
            return "Updating readings, \(online)"
        }
        if safeAttentionCount > 0 {
            let noun = safeAttentionCount == 1 ? "miner needs" : "miners need"
            return "\(online), \(safeAttentionCount) \(noun) attention"
        }
        return online
    }

    private var reconnectingLabel: String {
        let count = min(reconnectingCount, safeTotalCount)
        return "Reconnecting to \(count) \(count == 1 ? "miner" : "miners")"
    }

    static func emptySearchTitle(for query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "No miners yet"
            : "No matching miners"
    }

    static func emptySearchMessage(for query: String) -> String {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return "Add a miner to see its status, hashrate and temperature here."
        }
        return "Try a different name, address or ASIC model."
    }
}
