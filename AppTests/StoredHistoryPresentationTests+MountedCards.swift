import Foundation
import Testing
import SwiftUI
import HashFleetCore
@testable import HashFleet

extension StoredHistoryPresentationTests {
    // MARK: - Mounted View Integration Tests with Isolated Database

    @Test
    func freshFleetHistoryCardLoadsIsolatedDatabaseAndRendersStoredMean() async throws {
        let privateDB = MinerTelemetryDatabase(inMemory: true)
        let minerId = UUID()
        let now = Date()

        // Insert historical readings spaced across the past 30 minutes
        for offset in stride(from: -1500.0, through: -100.0, by: 200.0) {
            privateDB.recordReading(
                minerId: minerId.uuidString,
                timestamp: now.addingTimeInterval(offset),
                reading: MinerReadingInput(hashrate: 600.0)
            )
        }
        await privateDB.flushReadings()

        let device = MinerDevice(id: minerId, name: "Isolated Gamma", address: "192.168.1.210", kind: .espMiner)
        // Cold start: empty live snapshots in memory
        let card = FleetHistoryCard(
            devices: [device],
            snapshots: [:],
            isDemo: false,
            initialDisplay: .miners,
            initialRecentRange: .hour,
            database: privateDB
        )

        let rendered = try await FleetViewRenderHarness.render(
            card,
            width: 800,
            height: 1_200,
            readiness: { view in
                view.visibleText.contains("600")
                    && view.visibleText.contains("1-minute average per-miner reading")
            }
        )

        #expect(rendered.visibleText.contains("Recorded hashrate history"))
        #expect(rendered.visibleText.contains("1-minute average per-miner reading"))
        #expect(rendered.visibleText.contains("600"))
        #expect(rendered.visibleText.contains("Isolated Gamma"))
        #expect(!rendered.visibleText.contains("Simulated hashrate history"))
    }

    @Test
    func secondNewCardInstanceAgainstSameDatabaseShowsSavedHistory() async throws {
        let privateDB = MinerTelemetryDatabase(inMemory: true)
        let minerId = UUID()
        let now = Date()

        for offset in stride(from: -800.0, through: -100.0, by: 150.0) {
            privateDB.recordReading(
                minerId: minerId.uuidString,
                timestamp: now.addingTimeInterval(offset),
                reading: MinerReadingInput(hashrate: 750.0)
            )
        }
        await privateDB.flushReadings()

        let device = MinerDevice(id: minerId, name: "Persistent Rig", address: "192.168.1.212", kind: .espMiner)

        // First instance
        let firstCard = FleetHistoryCard(
            devices: [device],
            snapshots: [:],
            isDemo: false,
            initialDisplay: .miners,
            initialRecentRange: .hour,
            database: privateDB
        )
        let firstRender = try await FleetViewRenderHarness.render(
            firstCard,
            width: 800,
            height: 1_200,
            readiness: { $0.visibleText.contains("750") }
        )
        #expect(firstRender.visibleText.contains("750"))

        // Second distinct instance representing a subsequent screen or relaunch against the same DB
        let secondCard = FleetHistoryCard(
            devices: [device],
            snapshots: [:],
            isDemo: false,
            initialDisplay: .miners,
            initialRecentRange: .hour,
            database: privateDB
        )
        let secondRender = try await FleetViewRenderHarness.render(
            secondCard,
            width: 800,
            height: 1_200,
            readiness: { $0.visibleText.contains("750") }
        )
        #expect(secondRender.visibleText.contains("750"))
        #expect(secondRender.visibleText.contains("Persistent Rig"))
    }

    @Test
    func demoModeCardDoesNotReadSuppliedSavedDatabase() async throws {
        let privateDB = MinerTelemetryDatabase(inMemory: true)
        let minerId = UUID()
        let now = Date()

        // Populate database with distinct non-demo value
        privateDB.recordReading(
            minerId: minerId.uuidString,
            timestamp: now.addingTimeInterval(-300),
            reading: MinerReadingInput(hashrate: 999.0)
        )
        await privateDB.flushReadings()

        let device = MinerDevice(id: minerId, name: "Demo Miner", address: "192.168.1.215", kind: .espMiner)
        // With isDemo: true, loadHistoricalData guards early and never reads the database
        let card = FleetHistoryCard(
            devices: [device],
            snapshots: [:],
            isDemo: true,
            initialDisplay: .miners,
            initialRecentRange: .hour,
            database: privateDB
        )

        let rendered = try await FleetViewRenderHarness.render(
            card,
            width: 800,
            height: 1_200,
            readiness: { $0.visibleText.contains("Simulated hashrate history") }
        )

        #expect(rendered.visibleText.contains("Simulated hashrate history"))
        #expect(!rendered.visibleText.contains("999"))
        #expect(!rendered.visibleText.contains("Recorded hashrate history"))
    }
}
