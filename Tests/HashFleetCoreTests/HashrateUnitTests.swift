import Testing
@testable import HashFleetCore

@Suite("Hashrate Formatting and Auto-scaling Tests")
struct HashrateUnitTests {
    @Test("Legacy GH/s and TH/s outputs remain intact")
    func testLegacyExpectedStrings() {
        #expect(FleetFormat.hashrateWithUnit(750) == "750 GH/s")
        #expect(FleetFormat.hashrateWithUnit(1_529) == "1.53 TH/s")
        #expect(FleetFormat.hashrateWithUnit(2.40 * 1_000) == "2.40 TH/s")
    }

    @Test("Legacy GH/s and MH/s preserve 0...2 fraction digits")
    func testFractionDigitsPreserved() {
        // GH/s preserves up to 2 fraction digits if present, rather than losing precision
        #expect(FleetFormat.hashrateWithUnit(512.5) == "512.5 GH/s")
        #expect(FleetFormat.hashrateWithUnit(1.25) == "1.25 GH/s")
        #expect(FleetFormat.hashrateWithUnit(0.00125) == "1.25 MH/s")
        #expect(FleetFormat.hashrateWithUnit(0.5125) == "512.5 MH/s")
        #expect(FleetFormat.hashrateWithUnit(0.00000213909) == "2.14 kH/s")
    }

    @Test("Auto-scaling propagates across magnitudes")
    func testAutoScaling() {
        // H/s range
        #expect(FleetFormat.hashrateWithUnit(0.000_000_123) == "123.00 H/s")
        // kH/s range
        #expect(FleetFormat.hashrateWithUnit(0.000_123) == "123.00 kH/s")
        // MH/s range
        #expect(FleetFormat.hashrateWithUnit(0.123) == "123 MH/s")
        // GH/s range
        #expect(FleetFormat.hashrateWithUnit(123) == "123 GH/s")
        // TH/s range
        #expect(FleetFormat.hashrateWithUnit(123_000) == "123.00 TH/s")
        // PH/s range
        #expect(FleetFormat.hashrateWithUnit(123_000_000) == "123.00 PH/s")
        // EH/s range
        #expect(FleetFormat.hashrateWithUnit(123_000_000_000) == "123.00 EH/s")
    }

    @Test("Values near 1000 properly promote using actual 2 decimal rounding rules")
    func testRoundingPromotions() {
        // 999.999 MH/s rounded to 2 digits is 1000.00 MH/s, so it MUST promote to 1.00 GH/s
        #expect(FleetFormat.hashrateWithUnit(0.999_999) == "1 GH/s") // formats as 1 GH/s due to 0...2 precision

        // 999.999 GH/s rounded to 2 digits is 1000.00 GH/s, so it MUST promote to 1.00 TH/s
        #expect(FleetFormat.hashrateWithUnit(999.999) == "1.00 TH/s")

        // 999.6 GH/s rounded to 2 digits is 999.60, so it remains GH/s
        #expect(FleetFormat.hashrateWithUnit(999.6) == "999.6 GH/s")
    }

    @Test("Low positive values expand precision or use scientific rather than rounding to zero")
    func testTinyValues() {
        #expect(FleetFormat.hashrateWithUnit(0.000_000_000_1) == "0.10 H/s")
        #expect(FleetFormat.hashrateWithUnit(1e-20) == "1E-11 H/s")

        let smallest = FleetFormat.hashrateWithUnit(hashesPerSecond: Double.leastNonzeroMagnitude)
        #expect(smallest.hasSuffix("H/s"))
        #expect(smallest != "0.00 H/s")
    }

    @Test("Zero paths reflect test legacy and explicit intentions")
    func testZeroValues() {
        // GH/s API 0 -> 0 GH/s
        #expect(FleetFormat.hashrateWithUnit(0) == "0 GH/s")

        // Exact H/s API 0 -> 0.00 H/s
        #expect(FleetFormat.hashrateWithUnit(hashesPerSecond: 0) == "0.00 H/s")
    }

    @Test("Invalid values, missing values, and infinities do not acquire units")
    func testInvalidAndExtremes() {
        #expect(FleetFormat.hashrateWithUnit(-1.0) == "—")
        #expect(FleetFormat.hashrateWithUnit(-500.0) == "—")
        #expect(FleetFormat.hashrateWithUnit(.infinity) == "—")
        #expect(FleetFormat.hashrateWithUnit(.nan) == "—")
        #expect(FleetFormat.hashrateUnit(-1.0) == "GH/s")
        #expect(FleetFormat.hashrateUnit(.nan) == "GH/s")

        // Max finite values shouldn't trap, they'll just format as EH/s safely.
        let largeValue = FleetFormat.hashrateWithUnit(Double.greatestFiniteMagnitude)
        #expect(largeValue.hasSuffix("EH/s"))
        #expect(largeValue.count < 32)
        #expect(!largeValue.localizedCaseInsensitiveContains("inf"))
        #expect(!largeValue.localizedCaseInsensitiveContains("nan"))
        #expect(largeValue.split(separator: " ").first?.contains("E") == true)
    }

    @Test(arguments: HashrateUnit.allCases)
    func fixedUnitFormattingRejectsInvalidValues(unit: HashrateUnit) {
        #expect(unit.formattedValue(fromGHs: -1) == "—")
        #expect(unit.formattedValue(fromGHs: .nan) == "—")
        #expect(unit.formattedValue(fromGHs: .infinity) == "—")
        #expect(unit.formatScaleValue(-1) == "—")
    }

    @Test("Exact H/s input formats correctly without normalization loss")
    func testExactHashesPerSecondAPI() {
        #expect(FleetFormat.hashrateWithUnit(hashesPerSecond: 500) == "500.00 H/s")
        #expect(FleetFormat.hashrateWithUnit(hashesPerSecond: 1_250) == "1.25 kH/s")
        #expect(FleetFormat.hashrateWithUnit(hashesPerSecond: 1_250_000) == "1.25 MH/s")
        #expect(FleetFormat.hashrateWithUnit(hashesPerSecond: 1_250_000_000) == "1.25 GH/s")
    }

    @Test("Unit APIs accurately expose scale factors")
    func testHashrateUnitAPI() {
        #expect(HashrateUnit.gigaHashesPerSecond.value(fromGHs: 2.5) == 2.5)
        #expect(HashrateUnit.teraHashesPerSecond.value(fromGHs: 2500) == 2.5)
        #expect(HashrateUnit.megaHashesPerSecond.value(fromGHs: 0.0025) == 2.5)

        #expect(HashrateUnit.hashesPerSecond.value(fromHashesPerSecond: 2.5) == 2.5)

        #expect(HashrateUnit.teraHashesPerSecond.formattedValue(fromGHs: 2500) == "2.50")
        #expect(HashrateUnit.gigaHashesPerSecond.formattedValue(fromGHs: 2.5) == "2.5")
    }
}
