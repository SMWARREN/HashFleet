import Foundation
import PDFKit
import Testing
@testable import HashFleet

/// Native PDF renderer tests. These require the iOS test host and do not replace visual or share-sheet acceptance.
@MainActor
struct FleetReportPDFTests {
    @Test func reportPDFRendersAutoScaledHashratesForBothSubtotalAndMiners() throws {
        let miner1 = FleetReportFixtures.miner(id: 1, hashrate: 2_500.0)    // 2.50 TH/s ASIC
        let miner2 = FleetReportFixtures.miner(id: 2, hashrate: 750.0)      // 750 GH/s ASIC
        let miner3 = FleetReportFixtures.miner(id: 3, hashrate: nil)        // missing
        let miner4 = FleetReportFixtures.miner(id: 4, hashrate: 0.0000025)  // 2.50 kH/s CPU
        let report = FleetReportFixtures.report([miner1, miner2, miner3, miner4])

        let data = FleetReportPDF.render(report)
        let document = try #require(PDFDocument(data: data))
        let text = try #require(document.string)

        // Subtotal (2500 + 750 + 0.0000025 = 3250.0000025 GH/s = 3.25 TH/s)
        #expect(text.contains("Hashrate subtotal: 3.25 TH/s"))
        // Miner 1 auto-scales to TH/s
        #expect(text.contains("Hashrate: 2.50 TH/s"))
        // Miner 2 retains GH/s
        #expect(text.contains("Hashrate: 750 GH/s"))
        // Miner 3 missing hashrate is truthfully "Not reported" without unit suffix
        #expect(text.contains("Hashrate: Not reported"))
        #expect(!text.contains("Not reported GH/s"))
        // Miner 4 CPU miner retains kH/s
        #expect(text.contains("Hashrate: 2.50 kH/s"))
        // Anonymous labels preserved
        #expect(text.contains("Miner 1"))
        #expect(text.contains("Miner 2"))
        #expect(text.contains("Miner 3"))
        #expect(text.contains("Miner 4"))
    }

    @Test func emptyReportIsAReadableSinglePagePDF() throws {
        let data = FleetReportPDF.render(FleetReportFixtures.report([]))
        #expect(data.starts(with: Data("%PDF".utf8)))
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 1)
        let text = try #require(document.string)
        #expect(text.contains("No miners"))
        #expect(text.contains("2023-11-14T22:13:20Z"))
        #expect(text.contains("not a daily report"))
        #expect(text.contains("Not reported"))
        #expect(text.contains("Page 1"))
    }

    @Test func largeFleetPaginatesWithoutDroppingMinersAndLabelsDemoAndStaleData() throws {
        let miners = (1...100).map { index in
            FleetReportFixtures.miner(id: index, freshness: index == 1 ? .stale : .fresh)
        }
        let data = FleetReportPDF.render(FleetReportFixtures.report(miners, isDemo: true))
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount > 1)
        let text = try #require(document.string)
        #expect(text.contains("DEMO / SIMULATED READINGS"))
        #expect(text.contains("Stale at capture"))
        #expect(text.contains("Excluded from subtotals"))
        for index in 1...100 {
            #expect(text.contains("Miner \(index)\n"), "Every miner must survive pagination")
        }
        for index in 0..<document.pageCount {
            let page = try #require(document.page(at: index))
            let pageText = try #require(page.string)
            #expect(pageText.contains("HASH FLEET"))
            #expect(!pageText.localizedCaseInsensitiveContains("axe fleet"))
            #expect(pageText.contains("Page \(index + 1)"))
            #expect(page.bounds(for: .mediaBox).width == 612)
            #expect(page.bounds(for: .mediaBox).height == 792)
        }
    }
}
