import Foundation
import SwiftUI
import Testing
@testable import HashFleet
@testable import HashFleetWidgetTestSupport

@Suite("App and widget presentation consistency", .serialized) @MainActor
struct FleetGlancePresentationConsistencyTests {
    @Test(arguments: [false, true])
    func demoPreviewUsesTheWidgetsDemoAndNoConnectionCopy(showsDetails: Bool) async throws {
        let now = Date()
        let glance = HashFleet.FleetGlance(updatedAt: now, onlineCount: 2, minerCount: 3,
            hashrateGHs: 2_400.5, powerWatts: 38.25, isDemo: true)
        for scheme in [ColorScheme.light, .dark] {
            let rendered = try await preview(glance, showsDetails: showsDetails, scheme: scheme)
            #expect(rendered.visibleText.contains("DEMO"))
            #expect(rendered.visibleText.contains("Sample data"))
            #expect(rendered.visibleText.contains("no connection"))
            #expect(!rendered.visibleText.contains("online"))
        }
    }

    @Test(arguments: [false, true])
    func stalePreviewWarnsThatTheCountsAndRateAreHistorical(showsDetails: Bool) async throws {
        let glance = HashFleet.FleetGlance(updatedAt: Date(timeIntervalSinceNow: -120),
            onlineCount: 2, minerCount: 3, hashrateGHs: 2_400.5, powerWatts: 38.25, isDemo: false)
        for scheme in [ColorScheme.light, .dark] {
            let rendered = try await preview(glance, showsDetails: showsDetails, scheme: scheme)
            #expect(rendered.visibleText.contains("STALE"))
            #expect(rendered.visibleText.contains("Last known"))
            #expect(rendered.visibleText.contains("open app to refresh"))
            #expect(!rendered.visibleText.contains("online"))
        }
    }

    @Test(arguments: [false, true])
    func emptyPreviewDoesNotAttachUnitsToAnAbsentReading(showsDetails: Bool) async throws {
        let rendered = try await preview(.empty, showsDetails: showsDetails, scheme: .dark)
        #expect(rendered.visibleText.contains("GET STARTED"))
        #expect(!rendered.visibleText.contains("GH/s"))
        #expect(!rendered.visibleText.contains("TH/s"))
        #expect(!rendered.visibleText.contains(" W"))
        #expect(!rendered.visibleText.contains("0 W"))
    }

    @Test(arguments: [
        "Refresh failed · saved reading",
        "Refresh timed out · saved reading",
        "Refresh stopped · saved reading",
        "Open app to prepare refresh"
    ])
    func widgetSummaryIncludesTheVisibleRefreshResultWithoutChangingTheReading(message: String) {
        let now = Date()
        let savedAt = now.addingTimeInterval(-90)
        let entry = HashFleetWidgetTestSupport.FleetWidgetEntry(date: now,
            glance: .init(updatedAt: savedAt, onlineCount: 2, minerCount: 3,
                hashrateGHs: 2_400.5, powerWatts: 38.25, isDemo: false),
            refresh: .init(isEnabled: true, message: message))
        #expect(entry.presentation.accessibilitySummary.contains(message))
        #expect(entry.presentation.accessibilitySummary.contains("2.40 TH/s"))
        #expect(entry.presentation.accessibilitySummary.contains("Stale snapshot"))
        #expect(entry.glance.updatedAt == savedAt)
        #expect(!entry.presentation.redactedAccessibilitySummary.contains("2.40"))
        #expect(!entry.presentation.redactedAccessibilitySummary.contains("38"))
        #expect(!entry.presentation.redactedAccessibilitySummary.contains(message))
    }

    @Test(arguments: [-5.001, -5.0, 0.0, 59.999, 60.0, 120.0])
    func appAndWidgetPoliciesAgreeAtFreshnessAndClockBoundaries(age: Double) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for demo in [false, true] {
            let updatedAt = now.addingTimeInterval(-age)
            let glance = HashFleet.FleetGlance(updatedAt: updatedAt, onlineCount: 2, minerCount: 3,
                hashrateGHs: 2_400.5, powerWatts: 38.25, isDemo: demo)
            let app = HashFleet.FleetGlancePreviewCard(glance: glance, showsDetails: true,
                referenceDate: now).presentation
            let widget = HashFleetWidgetTestSupport.FleetGlancePresentation(
                glance: .init(updatedAt: updatedAt, onlineCount: 2, minerCount: 3,
                    hashrateGHs: 2_400.5, powerWatts: 38.25, isDemo: demo),
                isStale: age >= 60 || age < -5)
            #expect(app.isStale == widget.isStale)
            #expect(app.badge == widget.badge)
            #expect(app.rateLabel == widget.rateLabel)
            #expect(app.rate == widget.rate && app.rateUnit == widget.rateUnit)
            #expect(app.power == widget.power)
            #expect(app.efficiencyJPerTH == widget.efficiencyJPerTH)
            #expect(app.status == widget.status)
            #expect(app.accessibilitySummary == widget.accessibilitySummary)
            #expect(app.redactedAccessibilitySummary == widget.redactedAccessibilitySummary)
            #expect(app.glance.updatedAt == updatedAt)
            if demo { #expect(app.status == "Sample data · no connection") }
        }
    }

    @Test
    func zeroAndInvalidMeasurementsRemainDistinctInBothCompiledModules() {
        let now = Date()
        for (rate, power) in [(0.0, 0.0), (750.0, 19.0), (2_400.5, 38.25),
                              (.nan, 19.0), (.infinity, 19.0), (-1.0, 19.0),
                              (1_200.0, .nan), (1_200.0, .infinity), (1_200.0, -1.0)] {
            let app = HashFleet.FleetGlancePresentation(glance: .init(updatedAt: now,
                onlineCount: 1, minerCount: 1, hashrateGHs: rate, powerWatts: power, isDemo: false), isStale: false)
            let widget = HashFleetWidgetTestSupport.FleetGlancePresentation(glance: .init(updatedAt: now,
                onlineCount: 1, minerCount: 1, hashrateGHs: rate, powerWatts: power, isDemo: false), isStale: false)
            #expect(app.hasMiners == widget.hasMiners)
            #expect(app.rate == widget.rate && app.rateUnit == widget.rateUnit)
            #expect(app.power == widget.power)
            if !rate.isFinite || !power.isFinite || rate < 0 || power < 0 {
                #expect(!app.hasMiners)
                #expect(app.rate == "—" && app.rateUnit.isEmpty && app.power == "—")
                #expect(app.efficiencyJPerTH == nil)
            } else if rate == 0 && power == 0 {
                #expect(app.hasMiners)
                #expect(app.rate == "0" && app.rateUnit == "GH/s" && app.power == "0")
                #expect(app.efficiencyJPerTH == nil)
            }
        }
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func realPreviewPixelsKeepSpacedPowerAndProtectAllReadingDetails(scheme: ColorScheme) async throws {
        let now = Date()
        let glance = HashFleet.FleetGlance(updatedAt: now, onlineCount: 2, minerCount: 3,
            hashrateGHs: 2_400.5, powerWatts: 38.25, isDemo: false)
        let content = HashFleet.FleetGlancePreviewCard(glance: glance, showsDetails: true)
            .preferredColorScheme(scheme)
        let regular = try await FleetViewRenderHarness.render(content, width: 390, height: 420)
        let hidden = try await FleetViewRenderHarness.render(content.redacted(reason: .privacy), width: 390, height: 420)
        #expect(regular.visibleText.contains("38 W"))
        #expect(!regular.visibleText.contains("38W"))
        #expect(regular.recognizesMetric("2.40", unit: "TH/s"))
        #expect(regular.visibleText.contains("2 of 3 online"))
        #expect(!hidden.recognizes("38"))
        #expect(!hidden.recognizes("2.40"))
        #expect(!hidden.recognizes("2 of 3"))
        #expect(hidden.pngData != regular.pngData)
    }

    @Test(arguments: [320.0, 520.0])
    func accessiblePreviewsKeepHistoricalStatusAndOriginalTimeVisible(width: Double) async throws {
        let savedAt = Date(timeIntervalSinceNow: -120)
        let glance = HashFleet.FleetGlance(updatedAt: savedAt, onlineCount: 2, minerCount: 3,
            hashrateGHs: 2_400.5, powerWatts: 38.25, isDemo: false)
        let content = HashFleet.FleetGlancePreviewCard(glance: glance, showsDetails: true)
            .dynamicTypeSize(.accessibility3)
        let rendered = try await FleetViewRenderHarness.render(content, width: width, height: 780)
        let savedTime = savedAt.formatted(.dateTime.hour().minute().locale(Locale(identifier: "en_US")))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(rendered.visibleText.contains("Last known"))
        #expect(rendered.visibleText.contains("open app to refresh"))
        #expect(rendered.visibleText.contains(savedTime))
        #expect(!rendered.visibleText.contains("online"))
    }

    private func preview(
        _ glance: HashFleet.FleetGlance, showsDetails: Bool, scheme: ColorScheme
    ) async throws -> FleetRenderedView {
        try await FleetViewRenderHarness.render(
            HashFleet.FleetGlancePreviewCard(glance: glance, showsDetails: showsDetails)
                .preferredColorScheme(scheme), width: 390, height: 420)
    }
}
