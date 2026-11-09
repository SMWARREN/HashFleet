//
//  AddMinerScanRadarTests.swift
//  MacAppTests
//
//  Tests for AddMinerScanRadar pure model logic.
//

import Foundation
import Testing
@testable import HashFleetMac

@Suite("Add Miner Scan Radar")
struct AddMinerScanRadarTests {
    @Test func progressClampingAndNormalFractions() {
        // Standard in-range fractions
        #expect(AddMinerScanRadarModel.progressFraction(probedHosts: 0, hostCount: 254) == 0.0)
        #expect(AddMinerScanRadarModel.progressFraction(probedHosts: 127, hostCount: 254) == 0.5)
        #expect(AddMinerScanRadarModel.progressFraction(probedHosts: 254, hostCount: 254) == 1.0)

        // Overflow clamping (probedHosts > hostCount)
        #expect(AddMinerScanRadarModel.progressFraction(probedHosts: 300, hostCount: 254) == 1.0)

        // Negative values clamping
        #expect(AddMinerScanRadarModel.progressFraction(probedHosts: -5, hostCount: 254) == 0.0)
    }

    @Test func zeroAndNegativeHostCountSafety() {
        // hostCount == 0 must return 0.0 without divide-by-zero crash
        #expect(AddMinerScanRadarModel.progressFraction(probedHosts: 0, hostCount: 0) == 0.0)
        #expect(AddMinerScanRadarModel.progressFraction(probedHosts: 10, hostCount: 0) == 0.0)

        // Negative host count safety
        #expect(AddMinerScanRadarModel.progressFraction(probedHosts: 10, hostCount: -50) == 0.0)
    }

    @Test func progressTextFormatting() {
        #expect(
            AddMinerScanRadarModel.progressText(probedHosts: 42, hostCount: 254) ==
            "Checked 42 of 254 addresses"
        )
        #expect(
            AddMinerScanRadarModel.progressText(probedHosts: 0, hostCount: 0) ==
            "Checked 0 of 0 addresses"
        )
    }

    @Test func foundCountFormatting() {
        #expect(AddMinerScanRadarModel.foundCountText(candidatesCount: 0) == "0 found")
        #expect(AddMinerScanRadarModel.foundCountText(candidatesCount: 1) == "1 found")
        #expect(AddMinerScanRadarModel.foundCountText(candidatesCount: 5) == "5 found")
    }

    @Test func percentTextFormatting() {
        #expect(AddMinerScanRadarModel.percentText(fraction: 0.0) == "0%")
        #expect(AddMinerScanRadarModel.percentText(fraction: 0.5) == "50%")
        #expect(AddMinerScanRadarModel.percentText(fraction: 0.456) == "46%")
        #expect(AddMinerScanRadarModel.percentText(fraction: 1.0) == "100%")
        // Clamped out of bounds
        #expect(AddMinerScanRadarModel.percentText(fraction: 1.5) == "100%")
        #expect(AddMinerScanRadarModel.percentText(fraction: -0.2) == "0%")
    }
}
