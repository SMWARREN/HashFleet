import Foundation
import PDFKit
import Testing
@testable import HashFleetMac

@Suite("Native macOS fleet report PDF")
struct FleetNativeReportTests {
    @MainActor
    @Test func rendersPaginatedSnapshotWithPrivacyMinimizedMinerRows() throws {
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let miners = (1...48).map { id in
            FleetReportSnapshot.Miner(
                id: id,
                connection: .online,
                freshness: .fresh,
                observedAt: capturedAt.addingTimeInterval(-30),
                hashrateGHs: 1.25,
                powerWatts: 18.5,
                temperatureCelsius: 54,
                fanRPM: 2_400,
                uptimeSeconds: 86_400
            )
        }
        let snapshot = FleetReportSnapshot(capturedAt: capturedAt, isDemo: false, miners: miners)

        let data = FleetReportPDF.render(snapshot)
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount > 1)

        let text = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
        #expect(text.contains("Fleet snapshot report"))
        #expect(text.contains("Miner 1"))
        #expect(text.contains("Miner 48"))
        #expect(text.contains("Hashrate subtotal"))
        #expect(text.contains("Power subtotal"))
        #expect(!text.contains("192.168."))
        #expect(!text.contains("example-wallet-123"))
        #expect(text.contains("Anonymous miner labels"))
    }

    @MainActor
    @Test func rendersAnEmptyFleetAsAValidSinglePagePDF() throws {
        let snapshot = FleetReportSnapshot(capturedAt: Date(timeIntervalSince1970: 1_800_000_000), isDemo: true, miners: [])

        let data = FleetReportPDF.render(snapshot)
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 1)
        #expect(document.page(at: 0)?.string?.contains("DEMO / SIMULATED READINGS") == true)
        #expect(document.page(at: 0)?.string?.contains("No miners in this fleet") == true)
    }
}
