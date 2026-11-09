import Foundation
import Testing
@testable import HashFleet

struct FleetReportCSVTests {
    @Test(arguments: ["=1+1", "+SUM(A1)", "-1+2", "@SUM(A1)", " \t=HYPERLINK(\"https://invalid\")", "\r\n+1", "\u{0000}=1"])
    func neutralizesSpreadsheetFormulaPrefixes(_ value: String) {
        #expect(FleetReportCSV.cell(value).hasPrefix("\"'"))
    }

    @Test func quotesAndLineBreaksAreEscapedWithoutChangingPlainText() {
        #expect(FleetReportCSV.cell("miner, \"A\"\r\nsecond line") == "\"miner, \"\"A\"\"\r\nsecond line\"")
        #expect(FleetReportCSV.cell("plain text") == "\"plain text\"")
        #expect(FleetReportCSV.cell("1.25") == "\"1.25\"")
        #expect(FleetReportCSV.cell("") == "\"\"")
    }

    @Test func emptyFleetStillExportsRectangularMetadataRow() throws {
        let text = String(bytes: FleetReportCSV.encode(FleetReportFixtures.report([])), encoding: .utf8) ?? ""
        let rows = text.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.components(separatedBy: "\",\"").count == 25 })
        #expect(text.contains("No miners"))
        #expect(text.contains("2023-11-14T22:13:20Z"))
        #expect(text.contains("Not reported"))
        #expect(text.hasSuffix("\r\n"))
    }

    @Test func exportHasUnitsCaptureScopeAndDemoLabelWithoutInventedHistory() {
        let report = FleetReportFixtures.report([
            FleetReportFixtures.miner(id: 1, hashrate: nil),
            FleetReportFixtures.miner(id: 2, freshness: .stale)
        ], isDemo: true)
        let text = String(bytes: FleetReportCSV.encode(report), encoding: .utf8) ?? ""
        let rows = text.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        #expect(rows.count == 3)
        #expect(rows.allSatisfy { $0.components(separatedBy: "\",\"").count == 25 })
        #expect(text.contains("hashrate_GHs"))
        #expect(text.contains("power_W"))
        #expect(text.contains("Demo / simulated"))
        #expect(text.contains("Stale at capture"))
        #expect(text.contains("\"No\""))
        #expect(text.contains("not a daily report"))
        #expect(!rows[0].contains("kWh"))
        #expect(!rows[0].contains("cost"))
    }

    @Test func canonicalHashrateColumnsRemainRawGHsMachineDataWithoutUnitCoercion() {
        let miner1 = FleetReportFixtures.miner(id: 1, hashrate: 2_500.0)
        let miner2 = FleetReportFixtures.miner(id: 2, hashrate: 750.0)
        let miner3 = FleetReportFixtures.miner(id: 3, hashrate: nil)
        let report = FleetReportFixtures.report([miner1, miner2, miner3])

        let text = String(bytes: FleetReportCSV.encode(report), encoding: .utf8) ?? ""
        let rows = text.components(separatedBy: "\r\n").filter { !$0.isEmpty }

        // Headers contain hashrate_subtotal_GHs and hashrate_GHs
        #expect(rows[0].contains("hashrate_subtotal_GHs"))
        #expect(rows[0].contains("hashrate_GHs"))

        // Subtotal (2500 + 750 = 3250) remains raw numeric GH/s
        #expect(rows[1].contains("\"3250.0\""))

        // Miner 1 raw GH/s machine value preserved
        #expect(rows[1].contains("\"2500.0\""))
        // Miner 2 raw GH/s machine value preserved
        #expect(rows[2].contains("\"750.0\""))
        // Miner 3 missing hashrate remains "Not reported"
        #expect(rows[3].contains("\"Not reported\""))

        // Machine data columns do NOT have human-readable TH/s strings coerced into raw fields
        #expect(!rows[1].contains("2.50 TH/s"))
    }
}
