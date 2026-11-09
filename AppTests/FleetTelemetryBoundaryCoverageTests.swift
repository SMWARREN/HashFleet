import Testing
import Foundation
@testable import HashFleet
import HashFleetCore

@Suite("Telemetry Boundary Coverage")
struct FleetTelemetryBoundaryCoverageTests {

    @Test("MinerDiagnosticsModel formatters reject non-finite and negative values")
    func testDiagnosticsFormattersBoundaryRejections() {
        let nan = Double.nan
        let inf = Double.infinity
        let negInf = -Double.infinity
        let neg: Double = -1.0

        // Ensure values strictly below zero or non-finite yield the expected placeholder
        let expectedPlaceholder = "Not reported"

        #expect(MinerDiagnosticsModel.formatHashrate(nan) == expectedPlaceholder)
        #expect(MinerDiagnosticsModel.formatHashrate(inf) == expectedPlaceholder)
        #expect(MinerDiagnosticsModel.formatHashrate(negInf) == expectedPlaceholder)
        #expect(MinerDiagnosticsModel.formatHashrate(neg) == expectedPlaceholder)

        #expect(MinerDiagnosticsModel.formatFrequency(neg) == expectedPlaceholder)
        #expect(MinerDiagnosticsModel.formatMillivolts(neg) == expectedPlaceholder)
        #expect(MinerDiagnosticsModel.formatVolts(neg) == expectedPlaceholder)
        #expect(MinerDiagnosticsModel.formatMilliamps(neg) == expectedPlaceholder)
        #expect(MinerDiagnosticsModel.formatWatts(neg) == expectedPlaceholder)
        #expect(MinerDiagnosticsModel.formatEnergyKWhPerDay(neg) == expectedPlaceholder)
        #expect(MinerDiagnosticsModel.formatTemperature(neg) == expectedPlaceholder)
        #expect(MinerDiagnosticsModel.formatFanRPM(neg) == expectedPlaceholder)
        #expect(MinerDiagnosticsModel.formatPercentage(neg) == expectedPlaceholder)
        #expect(MinerDiagnosticsModel.formatDuration(-10) == expectedPlaceholder)
        #expect(MinerDiagnosticsModel.formatHeapBytes(-100) == expectedPlaceholder)
    }

    @Test("MinerDiagnosticsModel formatters process zero and valid positive limits correctly without locale-fragile exact strings")
    func testDiagnosticsFormattersValidBoundaries() {
        let placeholder = "Not reported"

        // Hashrate
        let hashrateZero = MinerDiagnosticsModel.formatHashrate(0)
        #expect(hashrateZero != placeholder)
        #expect(hashrateZero.contains("0") && hashrateZero.contains("H/s"))

        // Voltage
        let voltsZero = MinerDiagnosticsModel.formatVolts(0)
        #expect(voltsZero != placeholder)
        #expect(voltsZero.contains("0") && voltsZero.hasSuffix("V"))

        // Fan RPM has specific explicit handling for 0
        #expect(MinerDiagnosticsModel.formatFanRPM(0) == "0 RPM (or stopped)")

        // Other formatters just ensure 0 is successfully formatted
        #expect(MinerDiagnosticsModel.formatFrequency(0) != placeholder)
        #expect(MinerDiagnosticsModel.formatMillivolts(0) != placeholder)
        #expect(MinerDiagnosticsModel.formatMilliamps(0) != placeholder)
        #expect(MinerDiagnosticsModel.formatWatts(0) != placeholder)
        #expect(MinerDiagnosticsModel.formatEnergyKWhPerDay(0) != placeholder)
        #expect(MinerDiagnosticsModel.formatTemperature(0) != placeholder)
        #expect(MinerDiagnosticsModel.formatPercentage(0) != placeholder)
        #expect(MinerDiagnosticsModel.formatDuration(0) != placeholder)
        #expect(MinerDiagnosticsModel.formatHeapBytes(0) != placeholder)
    }

    @Test("Share rejection parsing handles absent, negative, contradictory, and string fallback inputs")
    func testShareRejectionReasonsParsingBoundaries() {
        // Null / Missing
        #expect(MinerDiagnosticsModel.parseRejectionReasons(nil).isEmpty)
        #expect(MinerDiagnosticsModel.parseRejectionReasons(.null).isEmpty)
        #expect(MinerDiagnosticsModel.parseRejectionReasons(.array([])).isEmpty)

        // Negative count mapped to 0, zero count kept as 0
        let negativeCount = JSONValue.object(["message": .string("Low diff"), "count": .integer(-5)])
        let zeroCount = JSONValue.object(["reason": .string("Stale"), "count": .integer(0)])

        let reasons1 = MinerDiagnosticsModel.parseRejectionReasons(.array([negativeCount, zeroCount]))
        #expect(reasons1.count == 2)
        #expect(reasons1[0].message == "Low diff" && reasons1[0].count == 0)
        #expect(reasons1[1].message == "Stale" && reasons1[1].count == 0)

        // String fallback
        let stringFallback = JSONValue.array([.string("   "), .string("Network error")])
        let reasons2 = MinerDiagnosticsModel.parseRejectionReasons(stringFallback)
        #expect(reasons2.count == 1) // Empty strings discarded
        #expect(reasons2[0].message == "Network error" && reasons2[0].count == 0)

        // Missing message keys
        let missingMessage = JSONValue.array([.object(["count": .integer(3)])])
        let reasons3 = MinerDiagnosticsModel.parseRejectionReasons(missingMessage)
        #expect(reasons3.count == 1)
        #expect(reasons3[0].message == "Unknown rejection" && reasons3[0].count == 3)
    }

    @Test("MiningDifficultyFormat parse boundaries and unrepresentables")
    func testDifficultyFormatParseBoundaries() {
        // String parse
        #expect(MiningDifficultyFormat.parse("   ") == nil)
        #expect(MiningDifficultyFormat.parse("Not reported") == nil)
        #expect(MiningDifficultyFormat.parse("-1.5") == nil)
        #expect(MiningDifficultyFormat.parse("abc") == nil)
        #expect(MiningDifficultyFormat.parse("0") == Decimal(0))
        #expect(MiningDifficultyFormat.parse("100K") == Decimal(100_000))
        #expect(MiningDifficultyFormat.parse("1.5M") == Decimal(1_500_000))

        // Double parse
        #expect(MiningDifficultyFormat.parse(Double.nan) == nil)
        #expect(MiningDifficultyFormat.parse(Double.infinity) == nil)
        #expect(MiningDifficultyFormat.parse(-10.0) == nil)
        #expect(MiningDifficultyFormat.parse(Double(0)) == Decimal(0))

        // JSON parse
        #expect(MiningDifficultyFormat.parse(JSONValue.integer(-5)) == nil)
        #expect(MiningDifficultyFormat.parse(JSONValue.unsignedInteger(500)) == Decimal(500))
        #expect(MiningDifficultyFormat.parse(JSONValue.null) == nil)
        #expect(MiningDifficultyFormat.parse(JSONValue.bool(true)) == nil)
        #expect(MiningDifficultyFormat.parse(JSONValue.array([])) == nil)
        #expect(MiningDifficultyFormat.parse(JSONValue.object([:])) == nil)
    }

    @Test("MiningDifficultyFormat format string limits and unit bump edge cases")
    func testDifficultyFormatRoundingAndScaleBumping() {
        #expect(MiningDifficultyFormat.format(Decimal.nan) == "—")
        #expect(MiningDifficultyFormat.format(Decimal(-5)) == "—")

        #expect(MiningDifficultyFormat.format(Decimal(0)) == "0")

        // Keep small fractional numbers correctly
        #expect(MiningDifficultyFormat.format(Decimal(string: "0.000000000000005")!) == "0.000000000000005")

        // Values > 0 but rounding to 0 fallback
        #expect(MiningDifficultyFormat.format(Decimal(string: "0.0001")!) == "0.0001")

        // Scale bumping: 999.996K rounded to 2 digits is 1000.00K -> bumped to 1.00M
        #expect(MiningDifficultyFormat.format(Decimal(string: "999996")!) == "1.00M")
        #expect(MiningDifficultyFormat.format(Decimal(string: "999999999999999999")!) == "1.00E")

        // Regular abbreviation digits
        #expect(MiningDifficultyFormat.format(Decimal(string: "1234")!) == "1.23K")
        #expect(MiningDifficultyFormat.format(Decimal(string: "1234000")!) == "1.23M")

        // < 1000 scales
        #expect(MiningDifficultyFormat.format(Decimal(string: "15.6")!) == "15.6")
        #expect(MiningDifficultyFormat.format(Decimal(string: "150.2")!) == "150")
        #expect(MiningDifficultyFormat.format(Decimal(string: "0.55")!) == "0.55")
        #expect(MiningDifficultyFormat.format(Decimal(string: "9.99")!) == "9.99")
    }
}

extension FleetTelemetryBoundaryCoverageTests {
    @Test("MiningDifficultyFormat short delegates properly across types")
    func testDifficultyFormatShortWrapper() {
        #expect(MiningDifficultyFormat.short(JSONValue.integer(-5)) == nil)
        #expect(MiningDifficultyFormat.short(Double.nan) == nil)
        #expect(MiningDifficultyFormat.short(Decimal.nan) == nil)
        #expect(MiningDifficultyFormat.short("  ") == nil)

        #expect(MiningDifficultyFormat.short(JSONValue.unsignedInteger(5000)) == "5.00K")
        #expect(MiningDifficultyFormat.short(Double(1500000)) == "1.50M")
        #expect(MiningDifficultyFormat.short(Decimal(1000)) == "1.00K")
        #expect(MiningDifficultyFormat.short("0") == "0")
    }

    @Test("MinerDiagnosticsModel hashrateTrend clock/order boundary and truth tests")
    func testHashrateTrendBoundaries() {
        // Missing
        #expect(MinerDiagnosticsModel.hashrateTrend(recent1m: nil, baseline1h: 50) == nil)
        #expect(MinerDiagnosticsModel.hashrateTrend(recent1m: 50, baseline1h: nil) == nil)

        // Zero baseline is not a prediction baseline
        #expect(MinerDiagnosticsModel.hashrateTrend(recent1m: 50, baseline1h: 0) == nil)

        // Zero recent is handled safely (0 - 50) / 50 = -1, which is < -tolerance
        #expect(MinerDiagnosticsModel.hashrateTrend(recent1m: 0, baseline1h: 50) == .falling)

        // Exact equality
        #expect(MinerDiagnosticsModel.hashrateTrend(recent1m: 50, baseline1h: 50) == .steady)

        // Tolerance boundaries (default 0.02 = 2%)
        #expect(MinerDiagnosticsModel.hashrateTrend(recent1m: 102.0, baseline1h: 100) == .steady) // exactly +2%
        #expect(MinerDiagnosticsModel.hashrateTrend(recent1m: 102.1, baseline1h: 100) == .rising) // > 2%
        #expect(MinerDiagnosticsModel.hashrateTrend(recent1m: 98.0, baseline1h: 100) == .steady) // exactly -2%
        #expect(MinerDiagnosticsModel.hashrateTrend(recent1m: 97.9, baseline1h: 100) == .falling) // < -2%

        // Non-finite
        #expect(MinerDiagnosticsModel.hashrateTrend(recent1m: .infinity, baseline1h: 100) == nil)
        #expect(MinerDiagnosticsModel.hashrateTrend(recent1m: 100, baseline1h: .nan) == nil)

        // Negative (invalid)
        #expect(MinerDiagnosticsModel.hashrateTrend(recent1m: -10, baseline1h: 100) == nil)
        #expect(MinerDiagnosticsModel.hashrateTrend(recent1m: 100, baseline1h: -10) == nil)
    }

    @Test("MinerDiagnosticsModel.sanitizeStratumURL edge cases")
    func testSanitizeStratumURL() {
        // Already clean
        #expect(MinerDiagnosticsModel.sanitizeStratumURL("stratum+tcp://pool.com:3333") == "stratum+tcp://pool.com:3333")

        // With query
        #expect(MinerDiagnosticsModel.sanitizeStratumURL("stratum+tcp://pool.com:3333?user=xyz") == "stratum+tcp://pool.com:3333")

        // With fragment
        #expect(MinerDiagnosticsModel.sanitizeStratumURL("stratum+tcp://pool.com:3333#test") == "stratum+tcp://pool.com:3333")

        // With user/pass credentials (auth embedded)
        #expect(MinerDiagnosticsModel.sanitizeStratumURL("stratum+tcp://user:pass@pool.com:3333") == "stratum+tcp://pool.com:3333")

        // Bare host with user/pass
        #expect(MinerDiagnosticsModel.sanitizeStratumURL("user:pass@pool.com:3333") == "pool.com:3333")

        // "Not reported"
        #expect(MinerDiagnosticsModel.sanitizeStratumURL("Not reported") == "Not reported")

        // Empty
        #expect(MinerDiagnosticsModel.sanitizeStratumURL("   ") == nil)
    }

    @Test("MinerDiagnosticsModel.sanitizeConnectionInfo handles strings securely")
    func testSanitizeConnectionInfo() {
        // Safe words
        #expect(MinerDiagnosticsModel.sanitizeConnectionInfo("IPv4 TLS direct") == "IPv4 TLS direct")

        // Non-safe words
        #expect(MinerDiagnosticsModel.sanitizeConnectionInfo("Some random string") == nil)

        // Too long
        #expect(MinerDiagnosticsModel.sanitizeConnectionInfo("IPv4 direct connection with a really long string that is over 32 chars") == nil)

        // Empty
        #expect(MinerDiagnosticsModel.sanitizeConnectionInfo("   ") == nil)
    }
}
