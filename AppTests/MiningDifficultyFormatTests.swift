import Testing
import Foundation
import HashFleetCore
@testable import HashFleet

@Suite("Mining difficulty format tests")
struct MiningDifficultyFormatTests {

    // MARK: - String / SI Parsing & Short Abbreviation

    @Test func formatsStandardIntegerDifficultiesToShort() {
        #expect(MiningDifficultyFormat.short("0") == "0")
        #expect(MiningDifficultyFormat.short("1") == "1")
        #expect(MiningDifficultyFormat.short("42") == "42")
        #expect(MiningDifficultyFormat.short("999") == "999")
        #expect(MiningDifficultyFormat.short("1000") == "1.00K")
        #expect(MiningDifficultyFormat.short("1050") == "1.05K")
        #expect(MiningDifficultyFormat.short("16384") == "16.38K")
        #expect(MiningDifficultyFormat.short("450500") == "450.50K")
        #expect(MiningDifficultyFormat.short("392000000") == "392.00M")
    }

    @Test func formatsExact392000000To392M() {
        #expect(MiningDifficultyFormat.short("392000000") == "392.00M")
        #expect(MiningDifficultyFormat.short(392_000_000.0) == "392.00M")
        #expect(MiningDifficultyFormat.short(JSONValue.integer(392_000_000)) == "392.00M")
        #expect(MiningDifficultyFormat.short(JSONValue.string("392000000")) == "392.00M")
    }

    @Test func parsesSISuffixInputs() {
        #expect(MiningDifficultyFormat.short("450.5K") == "450.50K")
        #expect(MiningDifficultyFormat.short("3.45M") == "3.45M")
        #expect(MiningDifficultyFormat.short("1.25G") == "1.25G")
        #expect(MiningDifficultyFormat.short("2.1T") == "2.10T")
        #expect(MiningDifficultyFormat.short("500P") == "500.00P")
        #expect(MiningDifficultyFormat.short("1.5E") == "1.50E")
    }

    @Test func handlesRoundingAcrossScaleBoundaries() {
        // 999.6 rounds to 1000 -> promoted to 1.00K
        #expect(MiningDifficultyFormat.short("999.6") == "1.00K")
        // 999.4 rounds to 999 (no suffix, trims to integer)
        #expect(MiningDifficultyFormat.short("999.4") == "999")
        // 999,600 keeps two decimals at the K scale
        #expect(MiningDifficultyFormat.short("999600") == "999.60K")
        // 999,600,000 keeps two decimals at the M scale
        #expect(MiningDifficultyFormat.short("999600000") == "999.60M")
        // 999.99G keeps two decimals (does not promote)
        #expect(MiningDifficultyFormat.short("999990000000") == "999.99G")
        // A value that rounds past 999.995 at its scale promotes cleanly
        #expect(MiningDifficultyFormat.short("999999000000") == "1.00T")
    }

    @Test func preservesExactIntegerBeyondDouble53BitLimit() {
        let beyondLimit = "9007199254740993"  // 2^53 + 1
        let parsed = MiningDifficultyFormat.parse(beyondLimit)
        #expect(parsed == Decimal(string: "9007199254740993"))
        #expect(MiningDifficultyFormat.short(beyondLimit) == "9.01P")
        // 2^53 + 1 in exact P scale is 9.007...P -> 9.01P
    }

    @Test func parsesMaxInt64Exact() {
        let maxInt64Str = "9223372036854775807"
        let parsed = MiningDifficultyFormat.parse(maxInt64Str)
        #expect(parsed == Decimal(string: maxInt64Str))
        #expect(MiningDifficultyFormat.short(JSONValue.integer(Int64.max)) == "9.22E")
        // Int64.max in exact E scale is 9.223...E -> 9.22E
    }

    @Test func preservesTrueZeroHonesty() {
        #expect(MiningDifficultyFormat.short("0") == "0")
        #expect(MiningDifficultyFormat.short(0.0) == "0")
        #expect(MiningDifficultyFormat.short(Decimal(0)) == "0")
        #expect(MiningDifficultyFormat.short(JSONValue.integer(0)) == "0")
        #expect(MiningDifficultyFormat.short(JSONValue.unsignedInteger(0)) == "0")
        #expect(MiningDifficultyFormat.short(JSONValue.number(0)) == "0")
        #expect(MiningDifficultyFormat.short(JSONValue.string("0")) == "0")
    }

    @Test func formatsSubOneFractionalDifficultiesWithoutCollapsingToZero() {
        #expect(MiningDifficultyFormat.short("0.5") == "0.5")
        #expect(MiningDifficultyFormat.short("0.05") == "0.05")
        #expect(MiningDifficultyFormat.short("0.00123") == "0.00123")
        #expect(MiningDifficultyFormat.short("0.0000001") == "0.0000001")
        let tiny = "0.00000000000000000001"
        let formatted = MiningDifficultyFormat.short(tiny)
        #expect(formatted != "0")
        #expect(formatted.flatMap { Decimal(string: $0) } == Decimal(string: tiny))
    }

    @Test func rejectsNegativeAndNonfiniteDoubleSafely() {
        #expect(MiningDifficultyFormat.short(-1.0) == nil)
        #expect(MiningDifficultyFormat.short(Double.nan) == nil)
        #expect(MiningDifficultyFormat.short(Double.infinity) == nil)
        #expect(MiningDifficultyFormat.short(-Double.infinity) == nil)
        // Huge finite double that overflows Decimal representation
        #expect(MiningDifficultyFormat.short(Double.greatestFiniteMagnitude) == nil)
    }

    @Test func rejectsMalformedAndJunkStrings() {
        #expect(MiningDifficultyFormat.short("") == nil)
        #expect(MiningDifficultyFormat.short("   ") == nil)
        #expect(MiningDifficultyFormat.short("Not reported") == nil)
        #expect(MiningDifficultyFormat.short("NaN") == nil)
        #expect(MiningDifficultyFormat.short("Infinity") == nil)
        #expect(MiningDifficultyFormat.short("-500") == nil)
        #expect(MiningDifficultyFormat.short("123abc") == nil)
        #expect(MiningDifficultyFormat.short("abc") == nil)
        #expect(MiningDifficultyFormat.short("1.2.3") == nil)
    }

    @Test func rejectsUnsupportedJSONTypes() {
        #expect(MiningDifficultyFormat.short(JSONValue.null) == nil)
        #expect(MiningDifficultyFormat.short(JSONValue.bool(true)) == nil)
        #expect(MiningDifficultyFormat.short(JSONValue.bool(false)) == nil)
        #expect(MiningDifficultyFormat.short(JSONValue.array([])) == nil)
        #expect(MiningDifficultyFormat.short(JSONValue.object([:])) == nil)
    }
}
