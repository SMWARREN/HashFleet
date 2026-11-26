import Testing
import Foundation
@testable import HashFleetMac

/// The macOS sidebar keyboard focus order, tested as a pure function. Boundary cases cover
/// essentials with and without "more tools", full mode, and multiple miners. No view is hosted,
/// no store is created, and no network or socket is involved.
@Suite("Sidebar focus order evaluation")
@MainActor
struct SidebarFocusOrderEvaluationTests {
    private let analytics: [FleetSidebarDestination] = [.network, .energy, .achievements, .reports]

    @Test func fullModeIncludesAllSectionsInOrder() {
        let miners = [UUID(), UUID()]
        let order = FleetSidebarView.sidebarFocusOrder(
            filteredDevices: miners, analytics: analytics, isEssentials: false, showsMoreTools: false
        )
        #expect(order == [
            .overview, .miner(miners[0]), .miner(miners[1]),
            .network, .energy, .achievements, .reports,
            .backup, .monitoring, .about, .support
        ])
    }

    @Test func essentialsWithoutMoreToolsStopsAfterMonitoring() {
        let miner = UUID()
        let order = FleetSidebarView.sidebarFocusOrder(
            filteredDevices: [miner], analytics: analytics, isEssentials: true, showsMoreTools: false
        )
        #expect(order == [.overview, .miner(miner), .monitoring])
    }

    @Test func essentialsWithMoreToolsAddsAnalyticsAndSupport() {
        let order = FleetSidebarView.sidebarFocusOrder(
            filteredDevices: [], analytics: analytics, isEssentials: true, showsMoreTools: true
        )
        #expect(order == [
            .overview, .monitoring,
            .network, .energy, .achievements, .reports,
            .backup, .about, .support
        ])
    }

    @Test func emptyFleetKeepsOverviewAsFirstFocusTarget() {
        let order = FleetSidebarView.sidebarFocusOrder(
            filteredDevices: [], analytics: analytics, isEssentials: false, showsMoreTools: false
        )
        #expect(order.first == .overview)
        #expect(!order.contains(where: { if case .miner = $0 { return true } else { return false } }))
    }

    @Test func monitoringAppearsOnceInEachMode() {
        for essentials in [false, true] {
            for more in [false, true] {
                let order = FleetSidebarView.sidebarFocusOrder(
                    filteredDevices: [UUID()], analytics: analytics, isEssentials: essentials, showsMoreTools: more
                )
                let count = order.filter { $0 == .monitoring }.count
                #expect(count == 1, "essentials=\(essentials) more=\(more)")
            }
        }
    }
}
