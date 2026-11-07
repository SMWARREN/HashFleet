import SwiftUI
import Testing
@testable import HashFleetWidgetTestSupport

@Suite(.serialized) @MainActor
struct WidgetActivityComponentCoverageTests {
    enum Scenario: CaseIterable, Sendable { case empty, stale, demo }

    private func presentation(demo: Bool = false, empty: Bool = false, stale: Bool = false) -> HashFleetWidgetTestSupport.FleetGlancePresentation {
        let glance = HashFleetWidgetTestSupport.FleetGlance(
            updatedAt: Date(timeIntervalSince1970: 1_791_475_200),
            onlineCount: 2,
            minerCount: 3,
            hashrateGHs: 2_400.5,
            powerWatts: 38.25,
            isDemo: demo
        )
        return HashFleetWidgetTestSupport.FleetGlancePresentation(glance: empty ? .empty : glance, isStale: stale)
    }

    /// Checks copy recognized from captured pixels and verifies privacy-sensitive readings
    /// disappear from those pixels. This does not inspect accessibility labels.
    private func assertPrivacyPair<Content: View>(
        _ content: Content,
        visibleCopy: [String],
        privateCopy: [String],
        metrics: [(String, String)] = [],
        width: CGFloat,
        height: CGFloat
    ) async throws {
        let regular = try await FleetViewRenderHarness.render(content, width: width, height: height)
        let redacted = try await FleetViewRenderHarness.render(
            content.redacted(reason: .privacy), width: width, height: height
        )

        #expect(regular.pixelVariation > 0)
        for phrase in visibleCopy {
            #expect(regular.recognizes(phrase))
        }
        for phrase in privateCopy {
            #expect(regular.recognizes(phrase))
            #expect(!redacted.recognizes(phrase))
        }
        for (value, unit) in metrics {
            #expect(regular.recognizesMetric(value, unit: unit), "Expected spaced metric \(value) \(unit): \(regular.recognition)")
            #expect(!redacted.recognizes(value))
            #expect(!redacted.recognizesMetric(value, unit: unit))
        }
        #expect(redacted.pngData != regular.pngData)
    }

    private func renderPNG<Content: View>(
        _ content: Content,
        width: CGFloat,
        height: CGFloat
    ) async throws -> Data {
        let rendered = try await FleetViewRenderHarness.render(content, width: width, height: height)
        return rendered.pngData
    }

    @Test func rendersActualSmallWidgetContentWithPrivacyPair() async throws {
        let content = HashFleetWidgetTestSupport.FleetSmallWidget(
            presentation: presentation(),
            renderingMode: .fullColor
        )
        .background(HashFleetWidgetTestSupport.FleetWidgetTheme.canvas)

        try await assertPrivacyPair(
            content,
            visibleCopy: ["Hash Fleet", "RECENT"],
            privateCopy: ["2.40"],
            metrics: [("2.40", "TH/s")],
            width: 180,
            height: 180
        )
    }

    @Test func rendersActualMediumWidgetContentWithPrivacyPair() async throws {
        let content = HashFleetWidgetTestSupport.FleetMediumWidget(
            presentation: presentation(),
            renderingMode: .fullColor
        )
        .background(HashFleetWidgetTestSupport.FleetWidgetTheme.canvas)

        try await assertPrivacyPair(
            content,
            visibleCopy: ["FLEET HASHRATE"],
            privateCopy: ["2.40", "38"],
            metrics: [("2.40", "TH/s"), ("38", "W")],
            width: 360,
            height: 220
        )
    }

    @Test func rendersActualLargeWidgetContentWithPrivacyPair() async throws {
        let snapshot = presentation()
        #expect(snapshot.rateUnit == "TH/s")
        let content = HashFleetWidgetTestSupport.FleetLargeWidget(
            presentation: snapshot,
            renderingMode: .fullColor
        )
        .background(HashFleetWidgetTestSupport.FleetWidgetTheme.canvas)

        try await assertPrivacyPair(
            content,
            visibleCopy: ["FLEET HASHRATE", "FLEET POWER", "ONLINE STATUS"],
            privateCopy: ["2.40", "38"],
            metrics: [("2.40", "TH/s"), ("38", "W")],
            width: 360,
            height: 500
        )
    }

    @Test func rendersActualSmallSupplementalActivityContentWithPrivacyPair() async throws {
        let content = HashFleetWidgetTestSupport.FleetSmallSupplementalActivity(
            presentation: presentation()
        )
        .background(HashFleetWidgetTestSupport.FleetWidgetTheme.charcoal)

        try await assertPrivacyPair(
            content,
            visibleCopy: ["Hash Fleet", "RECENT", "2.40 TH/s", "2 of 3 online"],
            privateCopy: ["2.40 TH/s"],
            width: 320,
            height: 180
        )
    }

    @Test func rendersActualStandardLockScreenActivityContentWithPrivacyPair() async throws {
        let content = HashFleetWidgetTestSupport.FleetStandardLockScreenActivity(
            presentation: presentation()
        )
        .background(HashFleetWidgetTestSupport.FleetWidgetTheme.charcoal)

        try await assertPrivacyPair(
            content,
            visibleCopy: ["Hash Fleet", "RECENT", "FLEET HASHRATE"],
            privateCopy: ["2.40", "38"],
            metrics: [("2.40", "TH/s"), ("38", "W")],
            width: 390,
            height: 240
        )
    }

    @Test func rendersActualExpandedActivityContentWithPrivacyPair() async throws {
        let content = HashFleetWidgetTestSupport.FleetExpandedActivity(
            presentation: presentation()
        )
        .background(HashFleetWidgetTestSupport.FleetWidgetTheme.charcoal)

        try await assertPrivacyPair(
            content,
            visibleCopy: ["FLEET HASHRATE", "2.40 TH/s", "38 W", "2 of 3 online"],
            privateCopy: ["2.40 TH/s", "38 W"],
            width: 390,
            height: 200
        )
    }

    @Test func rendersActualActivityMetricsWithPrivacyPair() async throws {
        let content = HashFleetWidgetTestSupport.FleetActivityMetrics(
            presentation: presentation()
        )
        .background(HashFleetWidgetTestSupport.FleetWidgetTheme.charcoal)

        try await assertPrivacyPair(
            content,
            visibleCopy: ["FLEET HASHRATE", "2.40 TH/s", "POWER", "38 W"],
            privateCopy: ["2.40 TH/s", "38 W"],
            width: 360,
            height: 120
        )
    }

    @Test func systemWidgetContentComponentsHaveDistinctRealLayouts() async throws {
        let snapshot = presentation()
        let small = HashFleetWidgetTestSupport.FleetSmallWidget(
            presentation: snapshot,
            renderingMode: .fullColor
        ).background(HashFleetWidgetTestSupport.FleetWidgetTheme.canvas)
        let medium = HashFleetWidgetTestSupport.FleetMediumWidget(
            presentation: snapshot,
            renderingMode: .fullColor
        ).background(HashFleetWidgetTestSupport.FleetWidgetTheme.canvas)
        let large = HashFleetWidgetTestSupport.FleetLargeWidget(
            presentation: snapshot,
            renderingMode: .fullColor
        ).background(HashFleetWidgetTestSupport.FleetWidgetTheme.canvas)

        let smallPNG = try await renderPNG(small, width: 360, height: 500)
        let mediumPNG = try await renderPNG(medium, width: 360, height: 500)
        let largePNG = try await renderPNG(large, width: 360, height: 500)

        #expect(smallPNG != mediumPNG)
        #expect(smallPNG != largePNG)
        #expect(mediumPNG != largePNG)
    }

    @Test func lockScreenActivityContentComponentsHaveDistinctRealLayouts() async throws {
        let snapshot = presentation()
        let small = HashFleetWidgetTestSupport.FleetSmallSupplementalActivity(presentation: snapshot)
            .background(HashFleetWidgetTestSupport.FleetWidgetTheme.charcoal)
        let standard = HashFleetWidgetTestSupport.FleetStandardLockScreenActivity(presentation: snapshot)
            .background(HashFleetWidgetTestSupport.FleetWidgetTheme.charcoal)
        let expanded = HashFleetWidgetTestSupport.FleetExpandedActivity(presentation: snapshot)
            .background(HashFleetWidgetTestSupport.FleetWidgetTheme.charcoal)
        let metrics = HashFleetWidgetTestSupport.FleetActivityMetrics(presentation: snapshot)
            .background(HashFleetWidgetTestSupport.FleetWidgetTheme.charcoal)

        let smallPNG = try await renderPNG(small, width: 390, height: 240)
        let standardPNG = try await renderPNG(standard, width: 390, height: 240)
        let expandedPNG = try await renderPNG(expanded, width: 390, height: 240)
        let metricsPNG = try await renderPNG(metrics, width: 390, height: 240)

        #expect(smallPNG != standardPNG)
        #expect(standardPNG != expandedPNG)
        #expect(expandedPNG != metricsPNG)
        #expect(smallPNG != metricsPNG)
    }

    /// Direct body coverage only, not installed WidgetKit routing or Activity lifecycle.
    @Test(arguments: Scenario.allCases)
    func componentsKeepOnboardingStaleAndDemoCopyDistinct(_ state: Scenario) async throws {
        let snapshot = presentation(demo: state == .demo, empty: state == .empty, stale: state == .stale)
        let content = VStack(spacing: 16) {
            HashFleetWidgetTestSupport.FleetSmallWidget(presentation: snapshot, renderingMode: .accented)
                .frame(height: 200)
            HashFleetWidgetTestSupport.FleetMediumWidget(presentation: snapshot, renderingMode: .accented)
                .frame(height: 260)
            HashFleetWidgetTestSupport.FleetLargeWidget(presentation: snapshot, renderingMode: .accented)
                .frame(height: 500)
            HashFleetWidgetTestSupport.FleetSmallSupplementalActivity(presentation: snapshot)
                .frame(height: 180)
            HashFleetWidgetTestSupport.FleetStandardLockScreenActivity(presentation: snapshot)
                .frame(height: 260)
            HashFleetWidgetTestSupport.FleetExpandedActivity(presentation: snapshot)
                .frame(height: 200)
        }
        .padding(20)
        .background(HashFleetWidgetTestSupport.FleetWidgetTheme.charcoal)
        let rendered = try await FleetViewRenderHarness.render(content, width: 600, height: 1_900)
        switch state {
        case .empty:
            #expect(rendered.visibleText.contains("Open app to connect"))
            #expect(rendered.visibleText.contains("Your fleet starts in Hash Fleet."))
            #expect(rendered.visibleText.contains("Open Hash Fleet to connect your first miner"))
            #expect(!rendered.visibleText.contains("2.40 TH/s"))
        case .stale:
            #expect(rendered.visibleText.contains("STALE"))
            #expect(rendered.visibleText.contains("LAST KNOWN HASHRATE"))
            #expect(rendered.visibleText.contains("2.40 TH/s"))
            #expect(!rendered.visibleText.contains("SAMPLE HASHRATE"))
        case .demo:
            #expect(rendered.visibleText.contains("DEMO"))
            #expect(rendered.visibleText.contains("SAMPLE HASHRATE"))
            #expect(rendered.visibleText.contains("2.40 TH/s"))
            #expect(!rendered.visibleText.contains("LAST KNOWN HASHRATE"))
        }
    }
}
