//
//  FleetSidebarIconTileTests.swift
//  MacAppTests
//
//  Sidebar destinations get a colored icon tile (adapted from ShipSwift SWLabelWithIcon).
//

import Foundation
import Testing
@testable import HashFleetMac

@Suite("Sidebar icon tiles")
struct FleetSidebarIconTileTests {
    private let fixed: [FleetSidebarDestination] = [
        .overview, .network, .energy, .achievements, .reports, .backup, .monitoring, .about, .support
    ]

    @Test func everyFixedDestinationHasATile() {
        for destination in fixed {
            #expect(destination.iconStyle != nil, "\(destination.id) has no tile")
        }
    }

    @Test func minerRowsKeepTheirStatusDotInsteadOfATile() {
        #expect(FleetSidebarDestination.miner(UUID()).iconStyle == nil)
    }

    @Test func visibleSidebarTilesUseDistinctColors() {
        let tints = fixed.compactMap { $0.iconStyle?.tint }
        #expect(Set(tints).count == fixed.count)
    }

    @Test func symbolsMatchThePreviousSidebarMeaning() {
        #expect(FleetSidebarDestination.energy.iconStyle?.symbol == "bolt.fill")
        #expect(FleetSidebarDestination.achievements.iconStyle?.symbol == "trophy.fill")
        #expect(FleetSidebarDestination.monitoring.iconStyle?.symbol == "gearshape.fill")
    }

    @Test func titleColumnMatchesTileWidth() {
        #expect(FleetLayout.sidebarIconWidth == FleetSidebarIconTile.tileSize)
    }
}
