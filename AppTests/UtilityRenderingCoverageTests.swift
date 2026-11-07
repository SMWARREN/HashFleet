import Foundation
import SwiftUI
import Testing
import PDFKit
import HashFleetCore
@testable import HashFleet

/// Mounted utility-screen checkpoints backed by the shared URLProtocol-blocked fixture.
@Suite("Utility Rendering Coverage", .serialized)
@MainActor
struct UtilityRenderingCoverageTests {
    @Test("Network insights render sample, empty, and blocked public-data states")
    func networkInsightsSampleEmptyAndBlocked() async throws {
        let demo = try FleetRenderFixture(demo: true)
        defer { demo.cleanup() }
        await demo.insights.refresh()
        let sample = try await FleetViewRenderHarness.render(NavigationStack {
            NetworkInsightsView(fleet: demo.store, insights: demo.insights)
        }, width: 390, height: 1500)
        #expect(sample.pngData.count > 0 && sample.pixelVariation > 1)
        #expect(sample.visibleText.contains("Beyond your fleet"))
        #expect(sample.visibleText.contains("Sample network and pool data. No internet requests."))
        #expect(sample.visibleText.contains("Demo") && sample.visibleText.contains("not live"))
        #expect(demo.store.isDemo)

        let empty = try FleetRenderFixture(demo: false)
        defer { empty.cleanup() }
        let noData = try await FleetViewRenderHarness.render(NavigationStack {
            NetworkInsightsView(fleet: empty.store, insights: empty.insights)
        }, width: 390, height: 1500)
        #expect(noData.visibleText.contains("Load public data"))
        #expect(!noData.visibleText.contains("Unavailable"))

        let blocked = try FleetRenderFixture(demo: false)
        defer { blocked.cleanup() }
        blocked.store.preferences.externalDataEnabled = true
        await blocked.insights.refresh(force: true)
        let failed = try await FleetViewRenderHarness.render(NavigationStack {
            NetworkInsightsView(fleet: blocked.store, insights: blocked.insights)
        }, width: 390, height: 1500)
        #expect(failed.visibleText.contains("Beyond your fleet"))
        #expect(failed.visibleText.contains("Unavailable"))
        #expect(failed.visibleText.contains("Failed attempt"))
        #expect(failed.visibleText.contains("Load public data") || failed.visibleText.contains("Refresh public data"))
    }

    @Test("Pool stats hub renders external-data opt-out and no-configured-pools empty state")
    func poolStatsHubDisabledAndEmpty() async throws {
        let fixture = try FleetRenderFixture(demo: false)
        defer { fixture.cleanup() }
        let disabled = try await FleetViewRenderHarness.render(NavigationStack {
            PoolStatsHubView(fleet: fixture.store)
        }, width: 390, height: 1000)
        #expect(disabled.pngData.count > 0 && disabled.pixelVariation > 1)
        #expect(disabled.visibleText.contains("Your configured pools"))
        #expect(disabled.visibleText.contains("External data disabled"))
        #expect(disabled.visibleText.contains("Pool statistics require external data."))

        fixture.store.preferences.externalDataEnabled = true
        let empty = try await FleetViewRenderHarness.render(NavigationStack {
            PoolStatsHubView(fleet: fixture.store)
        }, width: 390, height: 1000)
        #expect(empty.visibleText.contains("No configured mining pools reported by online miners."))
        #expect(empty.visibleText.contains("CKPool, SoloFury or SoloPool"))
    }

    @Test("Electricity estimates render unknown readings and demo-simulated readings")
    func energyEmptyAndDemo() async throws {
        let emptyFixture = try FleetRenderFixture(demo: false)
        defer { emptyFixture.cleanup() }
        let empty = try await FleetViewRenderHarness.render(NavigationStack {
            FleetEnergyView(store: emptyFixture.store)
        }, width: 390, height: 1100)
        #expect(empty.pngData.count > 0 && empty.pixelVariation > 1)
        #expect(empty.visibleText.contains("Electricity estimates"))
        // Raw OCR can confuse a zero with the letter O. Assert the visible qualifier
        // separately from the real model counts, without correcting recognized digits.
        #expect(empty.visibleText.contains("miners have fresh power readings."))
        let emptyEstimate = FleetEnergyEstimate.capture(store: emptyFixture.store)
        #expect(emptyEstimate.reportingCount == 0 && emptyEstimate.deviceCount == 0)
        #expect(emptyEstimate.watts == nil && emptyEstimate.dailyKWh == nil)
        #expect(empty.visibleText.contains("Not reported"))
        #expect(empty.visibleText.contains("Set your rate"))
        #expect(empty.visibleText.contains("No currency conversion happens"))

        let demoFixture = try FleetRenderFixture(demo: true)
        defer { demoFixture.cleanup() }
        let sample = try await FleetViewRenderHarness.render(NavigationStack {
            FleetEnergyView(store: demoFixture.store)
        }, width: 390, height: 1100)
        #expect(sample.visibleText.contains("Demo / simulated power"))
        #expect(sample.visibleText.contains("miners have fresh power readings."))
        #expect(sample.visibleText.contains("not metered consumption"))
    }

    @Test("Fleet report view and PDF/CSV models preserve empty and sampled report meaning")
    func reportViewAndExportModels() async throws {
        let emptyFixture = try FleetRenderFixture(demo: false)
        defer { emptyFixture.cleanup() }
        let emptyView = try await FleetViewRenderHarness.render(NavigationStack {
            FleetReportView(store: emptyFixture.store)
        }, width: 390, height: 2_400)
        #expect(emptyView.pngData.count > 0 && emptyView.pixelVariation > 1)
        #expect(emptyView.visibleText.contains("Fleet Reports"))
        #expect(emptyView.visibleText.contains("No miners to report"))
        #expect(emptyView.visibleText.contains("You can still export this empty report."))
        #expect(emptyView.visibleText.contains("Preview PDF") && emptyView.visibleText.contains("Save CSV"))

        let capturedAt = Date()
        let sampleFixture = try FleetRenderFixture(demo: true)
        defer { sampleFixture.cleanup() }
        let sampleView = try await FleetViewRenderHarness.render(NavigationStack {
            FleetReportView(store: sampleFixture.store)
        }, width: 390, height: 3_400)
        #expect(sampleView.visibleText.contains("Demo / simulated readings"))
        #expect(!sampleView.visibleText.contains("No miners to report"))
        #expect(sampleView.pngData != emptyView.pngData)
        #expect(sampleView.visibleText.contains("Miner 1"))
        #expect(!sampleView.visibleText.contains(sampleFixture.store.devices.first?.name ?? "\u{0}"))

        let report = FleetReportSnapshot.capture(store: sampleFixture.store, at: capturedAt)
        #expect(report.isDemo)
        #expect(!report.miners.isEmpty)
        #expect(report.miners.first?.label == "Miner 1")
        #expect(report.miners.first?.label != sampleFixture.store.devices.first?.name)
        let csv = try #require(String(bytes: FleetReportCSV.encode(report), encoding: .utf8))
        #expect(csv.contains("Demo / simulated"))
        #expect(csv.contains("Anonymous miner labels"))
        #expect(!csv.contains(sampleFixture.store.devices.first?.name ?? "\u{0}"))

        let pdfData = FleetReportPDF.render(report)
        #expect(pdfData.starts(with: Data("%PDF".utf8)))
        let pdf = try #require(PDFDocument(data: pdfData))
        #expect(pdf.pageCount > 0)
        let pdfText = try #require(pdf.string)
        #expect(pdfText.contains("DEMO / SIMULATED READINGS"))
        #expect(pdfText.contains("Miner 1"))
        #expect(!pdfText.contains(sampleFixture.store.devices.first?.name ?? "\u{0}"))

        let emptyReport = FleetReportSnapshot.capture(store: emptyFixture.store, at: capturedAt)
        #expect(emptyReport.miners.isEmpty)
        #expect(emptyReport.hashrate.value == nil && emptyReport.power.value == nil)
        let emptyPDF = try #require(PDFDocument(data: FleetReportPDF.render(emptyReport)))
        #expect(emptyPDF.pageCount == 1)
        let emptyPDFText = try #require(emptyPDF.string)
        #expect(emptyPDFText.contains("No miners in this fleet"))
        let emptyCSV = try #require(String(bytes: FleetReportCSV.encode(emptyReport), encoding: .utf8))
        #expect(emptyCSV.contains("No miners"))
    }
}
