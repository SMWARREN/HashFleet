import SwiftUI
import Testing
@testable import HashFleetWidgetTestSupport
@testable import HashFleet

@MainActor
struct WidgetRenderingCoverageTests {
    private func glance(
        updatedAt: Date = Date(),
        online: Int = 2,
        total: Int = 3,
        hashrate: Double = 2_400.5,
        power: Double = 38.25,
        demo: Bool = false
    ) -> HashFleetWidgetTestSupport.FleetGlance {
        HashFleetWidgetTestSupport.FleetGlance(
            updatedAt: updatedAt,
            onlineCount: online,
            minerCount: total,
            hashrateGHs: hashrate,
            powerWatts: power,
            isDemo: demo
        )
    }

    /// Uses only the host-provided WidgetKit environment. The installed SDK declares
    /// EnvironmentValues.widgetFamily as get-only, so this makes no synthetic family selection.
    /// Separate component tests cover explicit layouts, not WidgetKit family routing.
    private func widgetView(_ snapshot: HashFleetWidgetTestSupport.FleetGlance) -> some View {
        let entry = HashFleetWidgetTestSupport.FleetWidgetEntry(date: Date(), glance: snapshot)
        return HashFleetWidgetTestSupport.FleetWidgetView(entry: entry)
    }

    @Test
    func fleetWidgetViewRendersUsingUnmodifiedHostEnvironment() async throws {
        let rendered = try await FleetViewRenderHarness.render(
            widgetView(glance()), width: 360, height: 220
        )

        #expect(rendered.pixelVariation > 1)
        #expect(rendered.visibleText.contains("2.40 TH/s"))
        #expect(!rendered.pngData.isEmpty)
    }

    /// These are the exact internal production accessory component types, rendered directly with
    /// a production FleetGlancePresentation. This covers their view bodies, not WidgetFamily routing.
    @Test
    func productionAccessoryComponentsRenderDirectlyWithoutSyntheticFamilySelection() async throws {
        let snapshot = glance()
        let presentation = HashFleetWidgetTestSupport.FleetGlancePresentation(
            glance: snapshot,
            isStale: false
        )
        let rendered = try await FleetViewRenderHarness.render(
            VStack(alignment: .leading, spacing: 8) {
                HashFleetWidgetTestSupport.FleetInlineWidget(presentation: presentation)
                HashFleetWidgetTestSupport.FleetCircularWidget(presentation: presentation)
                    .frame(width: 100, height: 100)
                HashFleetWidgetTestSupport.FleetRectangularWidget(presentation: presentation)
                    .frame(width: 220, height: 90)
            }
            .padding(12),
            width: 360,
            height: 300
        )

        #expect(rendered.pixelVariation > 1)
        #expect(rendered.visibleText.contains("Fleet"))
        #expect(rendered.visibleText.contains("FLEET"))
        #expect(rendered.visibleText.contains("Hash Fleet"))
    }

    @Test
    func emptyOnboardingAndFreshFleetHaveDistinctRenderedContent() async throws {
        let empty = try await FleetViewRenderHarness.render(
            widgetView(.empty), width: 360, height: 220
        )
        let fresh = try await FleetViewRenderHarness.render(
            widgetView(glance()), width: 360, height: 220
        )

        #expect(empty.visibleText.contains("Your fleet starts in Hash Fleet."))
        #expect(empty.visibleText.contains("Open the app to connect a miner and save your first snapshot."))
        #expect(!empty.visibleText.contains("2.40 TH/s"))
        #expect(fresh.visibleText.contains("2.40 TH/s"))
        #expect(empty.pngData != fresh.pngData, "onboarding must not render as cached telemetry")
    }

    @Test
    func staleSnapshotIsLabeledAndVisuallyDiffersFromRecentSnapshot() async throws {
        let recent = try await FleetViewRenderHarness.render(
            widgetView(glance()), width: 360, height: 220
        )
        let stale = try await FleetViewRenderHarness.render(
            widgetView(glance(updatedAt: Date().addingTimeInterval(-120))),
            width: 360,
            height: 220
        )

        #expect(recent.visibleText.contains("2.40 TH/s"))
        #expect(stale.visibleText.contains("LAST KNOWN HASHRATE"))
        #expect(stale.visibleText.contains("STALE"))
        #expect(stale.visibleText.contains("open app to refresh"))
        #expect(!stale.visibleText.contains("background refresh pending"))
        #expect(stale.pngData != recent.pngData, "stale state must visibly differ from the recent state")
    }

    @Test
    func demoSnapshotIsIdentifiedAsSampleData() async throws {
        let live = try await FleetViewRenderHarness.render(
            widgetView(glance()), width: 360, height: 220
        )
        let demo = try await FleetViewRenderHarness.render(
            widgetView(glance(demo: true)), width: 360, height: 220
        )

        #expect(demo.visibleText.contains("DEMO"))
        #expect(demo.visibleText.contains("2.40 TH/s"))
        #expect(demo.pngData != live.pngData, "demo labeling must be present in the rendered view")
    }

    @Test
    func privacyRedactionHidesMeasurementsButLeavesOnboardingReadable() async throws {
        let snapshot = glance()
        let empty = try await FleetViewRenderHarness.render(
            widgetView(.empty), width: 360, height: 220
        )
        let emptyRedacted = try await FleetViewRenderHarness.render(
            widgetView(.empty).redacted(reason: .privacy), width: 360, height: 220
        )
        let regular = try await FleetViewRenderHarness.render(
            widgetView(snapshot), width: 360, height: 220
        )
        let redacted = try await FleetViewRenderHarness.render(
            widgetView(snapshot).redacted(reason: .privacy), width: 360, height: 220
        )
        #expect(regular.visibleText.contains("2.40 TH/s"))
        #expect(empty.visibleText.contains("Your fleet starts in Hash Fleet."))
        #expect(emptyRedacted.visibleText.contains("Your fleet starts in Hash Fleet."))
        #expect(emptyRedacted.pngData == empty.pngData, "empty onboarding contains no privacy-sensitive reading")
        #expect(!redacted.visibleText.contains("2.40 TH/s"))
        #expect(!redacted.visibleText.contains("38 W"))
        #expect(redacted.pngData != regular.pngData, "privacy redaction must alter the visible telemetry surface")
    }

    @Test
    func reusableWidgetAndActivityChromeRendersWithRealThemeColors() async throws {
        let snapshot = glance(demo: true)
        let presentation = HashFleetWidgetTestSupport.FleetGlancePresentation(
            glance: snapshot,
            isStale: false
        )
        let rendered = try await FleetViewRenderHarness.render(
            VStack(alignment: .leading, spacing: 12) {
                HashFleetWidgetTestSupport.FleetWidgetBrand()
                HashFleetWidgetTestSupport.FleetInlineWidget(presentation: presentation)
                HashFleetWidgetTestSupport.FleetWidgetBrand(isActivity: true)
                HashFleetWidgetTestSupport.FleetWidgetTimestamp(date: snapshot.updatedAt, compact: true)
            }
            .padding(16)
            .background(HashFleetWidgetTestSupport.FleetWidgetTheme.canvas)
            .foregroundStyle(HashFleetWidgetTestSupport.FleetWidgetTheme.ink)
            .modifier(HashFleetWidgetTestSupport.FleetWidgetPrivacy(presentation: presentation)),
            width: 320,
            height: 150
        )

        #expect(rendered.visibleText.contains("Demo"))
        #expect(rendered.visibleText.contains("2.40 TH/s"))
        #expect(rendered.pixelVariation > 1)
    }
}
