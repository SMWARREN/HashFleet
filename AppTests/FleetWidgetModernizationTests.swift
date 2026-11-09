import Foundation
import Testing
@testable import HashFleet

@MainActor
struct FleetWidgetModernizationTests {
    private let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    private func sampleGlance(
        online: Int = 2,
        total: Int = 3,
        hashrate: Double = 2400.5,
        power: Double = 38.25,
        isDemo: Bool = false
    ) -> FleetGlance {
        FleetGlance(
            updatedAt: timestamp,
            onlineCount: online,
            minerCount: total,
            hashrateGHs: hashrate,
            powerWatts: power,
            isDemo: isDemo
        )
    }

    @Test
    func testElementRoleAccentingPolicy() {
        // Brand logo, badge, and primary metric should opt into accenting in tinted/accented mode
        #expect(FleetWidgetAppearancePolicy.isAccentable(role: .brandLogo) == true)
        #expect(FleetWidgetAppearancePolicy.isAccentable(role: .badge) == true)
        #expect(FleetWidgetAppearancePolicy.isAccentable(role: .primaryMetric) == true)

        // Secondary captions, timestamps, and static labels should stay unaccented to avoid overwhelming user tint
        #expect(FleetWidgetAppearancePolicy.isAccentable(role: .secondaryMetric) == false)
        #expect(FleetWidgetAppearancePolicy.isAccentable(role: .label) == false)
        #expect(FleetWidgetAppearancePolicy.isAccentable(role: .timestamp) == false)
    }

    @Test
    func testEfficiencyCalculationDerivedFromAggregates() {
        // Efficiency: (powerWatts * 1000) / hashrateGHs = J/TH
        // 38.25 W * 1000 / 2400.5 GH/s = 38250 / 2400.5 = 15.934 -> 15.9 J/TH
        let eff = FleetWidgetAppearancePolicy.formatEfficiency(hashrateGHs: 2400.5, powerWatts: 38.25)
        #expect(eff == "15.9")

        // Higher J/TH value (>= 100) formats without decimals
        // 500 W * 1000 / 2000 GH/s = 250 J/TH
        let highEff = FleetWidgetAppearancePolicy.formatEfficiency(hashrateGHs: 2000, powerWatts: 500)
        #expect(highEff == "250")

        // Zero or invalid hashrate/power returns nil (never fabricated or division-by-zero)
        #expect(FleetWidgetAppearancePolicy.formatEfficiency(hashrateGHs: 0, powerWatts: 50) == nil)
        #expect(FleetWidgetAppearancePolicy.formatEfficiency(hashrateGHs: -10, powerWatts: 50) == nil)
        #expect(FleetWidgetAppearancePolicy.formatEfficiency(hashrateGHs: 1000, powerWatts: -5) == nil)
        #expect(FleetWidgetAppearancePolicy.formatEfficiency(hashrateGHs: .infinity, powerWatts: 50) == nil)
        #expect(FleetWidgetAppearancePolicy.formatEfficiency(hashrateGHs: 1000, powerWatts: .nan) == nil)
    }

    @Test
    func testStaleTreatmentPolicy() {
        // Empty fleet does not require stale warning treatment
        #expect(FleetWidgetAppearancePolicy.requiresStaleTreatment(isStale: true, hasMiners: false) == false)
        // Fresh fleet with miners does not require stale warning treatment
        #expect(FleetWidgetAppearancePolicy.requiresStaleTreatment(isStale: false, hasMiners: true) == false)
        // Stale snapshot with actual miners requires stale treatment
        #expect(FleetWidgetAppearancePolicy.requiresStaleTreatment(isStale: true, hasMiners: true) == true)
    }

    @Test
    func testAccessibilitySummariesForRedactedAndUnredactedStates() {
        let fresh = sampleGlance()
        let freshSummary = FleetWidgetAppearancePolicy.accessibilitySummary(
            glance: fresh,
            isStale: false,
            isRedacted: false
        )
        #expect(freshSummary.contains("FLEET HASHRATE"))
        #expect(freshSummary.contains("2.40 TH/s"))
        #expect(freshSummary.contains("38 watts"))
        #expect(freshSummary.contains("2 of 3 online"))

        // When privacy redacted, custom VoiceOver summary protects sensitive readings
        let redactedSummary = FleetWidgetAppearancePolicy.accessibilitySummary(
            glance: fresh,
            isStale: false,
            isRedacted: true
        )
        #expect(
            redactedSummary == "Hash Fleet. Fleet readings are hidden for privacy. Open the app to view your fleet."
        )
        #expect(!redactedSummary.contains("2.40 TH/s"))
        #expect(!redactedSummary.contains("38 watts"))
    }

    @Test
    func testAccessibilitySummariesForDemoAndStaleStates() {
        let demoStale = sampleGlance(isDemo: true)
        let summary = FleetWidgetAppearancePolicy.accessibilitySummary(
            glance: demoStale,
            isStale: true,
            isRedacted: false
        )
        #expect(summary.contains("Demo sample data"))
        #expect(summary.contains("Stale snapshot"))
        #expect(summary.contains("SAMPLE HASHRATE"))
    }

    @Test
    func testEmptyFleetAccessibilitySummary() {
        let empty = FleetGlance.empty
        let summary = FleetWidgetAppearancePolicy.accessibilitySummary(
            glance: empty,
            isStale: true,
            isRedacted: false
        )
        #expect(summary == "Hash Fleet. No cached fleet. Open the app to connect a miner.")

        // Even if redacted, empty fleet remains clear with onboarding guidance
        let redactedEmpty = FleetWidgetAppearancePolicy.accessibilitySummary(
            glance: empty,
            isStale: true,
            isRedacted: true
        )
        #expect(redactedEmpty == "Hash Fleet. No cached fleet. Open the app to connect a miner.")
    }
}
