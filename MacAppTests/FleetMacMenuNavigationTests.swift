import Foundation
import SwiftUI
import Testing
@testable import HashFleetMac

@Suite("Native menu destination navigation")
@MainActor
struct FleetMacMenuNavigationTests {
    @Test func closesTransientMenuBeforeOpeningEveryDestination() {
        let id = UUID()
        for destination: FleetSidebarDestination in [.overview, .miner(id), .network, .energy, .achievements, .reports, .monitoring, .about, .support] {
            var events: [String] = []
            let navigation = FleetMacNavigationState()
            navigation.fleetPath.append("Previous child")
            FleetMacMenuNavigation.select(destination, dismiss: { events.append("dismiss") }, open: { selected in
                events.append("open")
                #expect(selected == destination)
                navigation.select(selected)
            })
            #expect(events == ["dismiss", "open"])
            #expect(navigation.sidebarSelection == destination)
            #expect(navigation.fleetPath.isEmpty)
        }
    }

    @Test func minerRoutesUseIdentityAndRemovedEntriesFallBackToOverview() {
        let first = UUID()
        let sameNameDifferentMiner = UUID()
        let ids: Set<UUID> = [first, sameNameDifferentMiner]
        #expect(FleetMacMenuNavigation.destination(minerID: first, availableIDs: ids) == .miner(first))
        #expect(FleetMacMenuNavigation.destination(minerID: sameNameDifferentMiner, availableIDs: ids) == .miner(sameNameDifferentMiner))
        #expect(FleetMacMenuNavigation.destination(minerID: UUID(), availableIDs: ids) == .overview)
        #expect(FleetMacMenuNavigation.destination(minerID: nil, availableIDs: ids) == .overview)
        #expect(FleetMacMenuNavigation.destination(minerID: first, availableIDs: []) == .overview)
    }
}
