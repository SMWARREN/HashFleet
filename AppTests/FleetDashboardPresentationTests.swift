import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

@Suite("Fleet dashboard presentation tests")
struct FleetDashboardPresentationTests {
    @Test("Miner status resolves loading, live, cached, stale and unreachable states")
    func minerStatusResolution() {
        #expect(FleetMinerPresentationState.resolve(isDemo: true, hasInfo: false, hasError: false, isLive: false) == .sample)
        #expect(FleetMinerPresentationState.resolve(isDemo: false, hasInfo: false, hasError: false, isLive: false) == .connecting)
        #expect(FleetMinerPresentationState.resolve(isDemo: false, hasInfo: true, hasError: false, isLive: false) == .online)
        #expect(FleetMinerPresentationState.resolve(isDemo: false, hasInfo: true, hasError: false, isLive: true) == .live)
        #expect(FleetMinerPresentationState.resolve(isDemo: false, hasInfo: true, hasError: true, isLive: false) == .stale)
        #expect(FleetMinerPresentationState.resolve(isDemo: false, hasInfo: false, hasError: true, isLive: false) == .unreachable)
        #expect(FleetMinerPresentationState.stale.isStale)
        #expect(!FleetMinerPresentationState.online.isStale)
    }

    @Test("Fleet list summary keeps primary online count prominent and attention concise")
    func listSummaryStates() {
        let healthy = FleetDashboardListSummary(
            totalCount: 3,
            onlineCount: 3,
            attentionCount: 0,
            isRefreshing: false
        )
        #expect(healthy.subtitle == "3 of 3 online")
        #expect(healthy.accessibilityLabel == "3 of 3 online")

        let attention = FleetDashboardListSummary(
            totalCount: 3,
            onlineCount: 2,
            attentionCount: 1,
            isRefreshing: false
        )
        #expect(attention.subtitle == "2 of 3 online · 1 needs attention")
        #expect(attention.accessibilityLabel == "2 of 3 online, 1 miner needs attention")

        let refreshing = FleetDashboardListSummary(
            totalCount: 3,
            onlineCount: 2,
            attentionCount: 2,
            isRefreshing: true
        )
        #expect(refreshing.subtitle == "Updating readings · 2 of 3 online")
        #expect(refreshing.accessibilityLabel == "Updating readings, 2 of 3 online")
    }

    @Test("Pending reconnect takes precedence over previous live and error states", arguments: [false, true])
    func pendingReconnectPresentation(hasInfo: Bool) {
        let pending = FleetMinerPresentationState.resolve(
            isDemo: false, hasInfo: hasInfo, hasError: true, isLive: true, isReconnecting: true
        )
        #expect(pending == .reconnecting)
        #expect(pending.title == "Reconnecting…")
        #expect(FleetMinerPresentationState.resolve(
            isDemo: true, hasInfo: hasInfo, hasError: true, isLive: true, isReconnecting: true
        ) == .sample)
    }

    @Test("Pending fleet checks do not announce old online or attention counts", arguments: [1, 3], [false, true])
    func reconnectingListSummary(count: Int, refreshing: Bool) {
        let summary = FleetDashboardListSummary(
            totalCount: 3, onlineCount: 0, attentionCount: 3, isRefreshing: refreshing,
            reconnectingCount: count
        )
        let label = "Reconnecting to \(count) \(count == 1 ? "miner" : "miners")"
        #expect(summary.subtitle == label + "…")
        #expect(summary.accessibilityLabel == label)
    }

    @Test("Fleet list summary handles empty and out-of-range counts safely")
    func listSummaryEmptyAndInvalidCounts() {
        let empty = FleetDashboardListSummary(
            totalCount: 0,
            onlineCount: 4,
            attentionCount: -1,
            isRefreshing: false
        )
        #expect(empty.subtitle == "Add a miner to start monitoring")
        #expect(empty.accessibilityLabel == "No miners added")

        let clamped = FleetDashboardListSummary(
            totalCount: 2,
            onlineCount: 9,
            attentionCount: -1,
            isRefreshing: false
        )
        #expect(clamped.subtitle == "2 of 2 online")
    }

    @Test("Fleet search empty state differentiates setup from no match")
    func emptySearchCopy() {
        #expect(FleetDashboardListSummary.emptySearchTitle(for: "  ") == "No miners yet")
        #expect(
            FleetDashboardListSummary.emptySearchMessage(for: "  ")
                == "Add a miner to see its status, hashrate and temperature here."
        )
        #expect(FleetDashboardListSummary.emptySearchTitle(for: "worker-7") == "No matching miners")
        #expect(
            FleetDashboardListSummary.emptySearchMessage(for: "worker-7")
                == "Try a different name, address or ASIC model."
        )
    }

    @Test("Miner presentation centralizes operational and visual state")
    func minerPresentationProperties() {
        #expect(FleetMinerPresentationState.live.isOperational)
        #expect(FleetMinerPresentationState.online.isOperational)
        #expect(!FleetMinerPresentationState.sample.isOperational)
        #expect(!FleetMinerPresentationState.reconnecting.isOperational)
        #expect(FleetMinerPresentationState.live.color == FleetTheme.positive)
        #expect(FleetMinerPresentationState.unreachable.color == FleetTheme.warning)
    }

    @Test("Hero refresh presentation resolves each monitoring mode")
    func heroRefreshPresentation() {
        #expect(FleetHeroRefreshPresentation.resolve(.init(
            isDemo: true, isInitialLoading: true, isRefreshing: true,
            realtimeMonitoring: true, liveConnectionCount: 1, liveFallbackCount: 1
        )).text == "SIMULATED")
        #expect(FleetHeroRefreshPresentation.resolve(.init(
            isDemo: false, isInitialLoading: true, isRefreshing: false,
            realtimeMonitoring: true, liveConnectionCount: 0, liveFallbackCount: 0
        )).showsProgress)
        #expect(FleetHeroRefreshPresentation.resolve(.init(
            isDemo: false, isInitialLoading: false, isRefreshing: false,
            realtimeMonitoring: true, liveConnectionCount: 1, liveFallbackCount: 0
        )).text == "REALTIME")
        #expect(FleetHeroRefreshPresentation.resolve(.init(
            isDemo: false, isInitialLoading: false, isRefreshing: false,
            realtimeMonitoring: true, liveConnectionCount: 0, liveFallbackCount: 1
        )).text == "HTTP FALLBACK")
    }

    @Test("All miner presentation state titles, colors, and connecting fallback")
    func minerPresentationStateTitlesAndColors() {
        #expect(FleetMinerPresentationState.sample.title == "Sample")
        #expect(FleetMinerPresentationState.loading.title == "Connecting")
        #expect(FleetMinerPresentationState.connecting.title == "Connecting")
        #expect(FleetMinerPresentationState.stale.title == "Unreachable")
        #expect(FleetMinerPresentationState.unreachable.title == "Unreachable")

        #expect(FleetMinerPresentationState.sample.color == FleetTheme.accent)
        #expect(FleetMinerPresentationState.loading.color == FleetTheme.secondary)
        #expect(FleetMinerPresentationState.connecting.color == FleetTheme.secondary)
        #expect(FleetMinerPresentationState.reconnecting.color == FleetTheme.secondary)
        #expect(FleetMinerPresentationState.stale.color == FleetTheme.warning)
    }

    @Test("Hero refresh presentation handles fallback and connecting states")
    func heroRefreshPresentationFallbackAndConnecting() {
        let pullOnly = FleetHeroRefreshPresentation.resolve(.init(
            isDemo: false, isInitialLoading: false, isRefreshing: false,
            realtimeMonitoring: false, liveConnectionCount: 0, liveFallbackCount: 0
        ))
        #expect(pullOnly.text == "ON OPEN / PULL")
        #expect(!pullOnly.showsProgress)
        #expect(pullOnly.usesMonospacedCaption)

        let connecting = FleetHeroRefreshPresentation.resolve(.init(
            isDemo: false, isInitialLoading: false, isRefreshing: false,
            realtimeMonitoring: true, liveConnectionCount: 0, liveFallbackCount: 0
        ))
        #expect(connecting.text == "CONNECTING LIVE")
        #expect(!connecting.showsProgress)
        #expect(connecting.usesMonospacedCaption)
    }

    @Test("Fleet attention summary correctly filters devices and fallbacks")
    func attentionSummaryResolution() {
        let dev1 = MinerDevice(id: UUID(), name: "Naja 1", address: "192.168.1.10")
        let dev2 = MinerDevice(id: UUID(), name: "Gamma 1", address: "192.168.1.11")
        let dev3 = MinerDevice(id: UUID(), name: "Reconnecting 1", address: "192.168.1.12")

        let snap1 = MinerSnapshot(info: nil, error: "Connection refused")
        let snap3 = MinerSnapshot(info: nil, error: nil, isReconnecting: true)

        let summary = FleetAttentionSummary(
            devices: [dev1, dev2, dev3],
            snapshots: [dev1.id: snap1, dev3.id: snap3],
            liveConnectionErrors: [dev2.id: "WebSocket dropped"]
        )

        #expect(summary.count == 2)
        #expect(summary.hasUnreachable)
        #expect(summary.needsAttention)
        #expect(summary.unreachable == [dev1])
        #expect(summary.liveFallbacks == [dev2])
    }

    @Test("Fleet list summary multiple attention count grammar")
    func listSummaryMultipleAttentionGrammar() {
        let multi = FleetDashboardListSummary(
            totalCount: 5,
            onlineCount: 3,
            attentionCount: 2,
            isRefreshing: false
        )
        #expect(multi.subtitle == "3 of 5 online · 2 need attention")
        #expect(multi.accessibilityLabel == "3 of 5 online, 2 miners need attention")
    }
}
