import Foundation
import Testing
@testable import HashFleetCore

/// Boundary coverage for wire-JSON → MinerInfo telemetry decoding that ModelTests and
/// MinerStatusSnapshotTests do not exercise: string-encoded numbers, unparsable metrics,
/// difficulty normalization across JSON types, MAC normalization, and derived-metric guards.
@Suite(.timeLimit(.minutes(1)))
struct TelemetryDecodingBoundaryTests {

    private func decode(_ body: String) throws -> MinerInfo {
        try JSONDecoder().decode(MinerInfo.self, from: Data(body.utf8))
    }

    @Test func stringEncodedCountersDecodeToTypedIntegers() throws {
        // APIClientTests already covers a string hashRate; counters keep exact Int semantics.
        let info = try decode(#"{"sharesAccepted":"17","uptimeSeconds":"3600"}"#)
        #expect(info.sharesAccepted == 17)
        #expect(info.uptimeSeconds == 3600)
    }

    @Test func unparsableStringMetricsFallBackToZero() throws {
        let info = try decode(#"{"hashRate":"booting","sharesAccepted":"n/a","temp":"--"}"#)
        #expect(info.hashRate == 0)
        #expect(info.sharesAccepted == 0)
        #expect(info.temp == 0)
    }

    @Test func fractionalSharesTruncateRatherThanRoundUp() throws {
        // integer() requires an exact post-truncation conversion; 17.9 must never report 18.
        let info = try decode(#"{"sharesAccepted":17.9,"sharesRejected":0.9}"#)
        #expect(info.sharesAccepted == 17)
        #expect(info.sharesRejected == 0)
    }

    @Test(arguments: [
        (#"{"bestDiff":512}"#, "512"),                    // integer wire form
        (#"{"bestDiff":1.25}"#, "1.25"),                  // fractional wire form
        (#"{"bestDiff":"  1.25G  "}"#, "1.25G"),          // firmware string form, whitespace trimmed
        (#"{"bestDiff":true}"#, "")                       // booleans are not difficulties
    ])
    func bestDiffNormalizesAcrossWireTypes(body: String, expected: String) throws {
        #expect(try decode(body).bestDiff == expected)
    }

    @Test(arguments: [
        (#"{"macAddr":"dc:b4:5f:11:22:33"}"#, "DCB45F112233"),
        (#"{"macAddr":"DC-B4-5F-11-22-33"}"#, "DCB45F112233"),
        (#"{"macAddr":"dcb45f112233"}"#, "DCB45F112233"),
        (#"{"macAddr":"dc:b4:5f"}"#, ""),                 // too short to be a MAC
        (#"{"macAddr":""}"#, "")
    ])
    func macAddressNormalizesSeparatorsCaseAndRejectsShortValues(body: String, expected: String) throws {
        #expect(try decode(body).macAddress == expected)
    }

    @Test func hostnameFallsBackAcrossKnownFirmwareKeys() throws {
        #expect(try decode(#"{"fullHostname":"gamma-221.local"}"#).hostname == "gamma-221.local")
        #expect(try decode(#"{"mdnsHostname":"najaduo.local"}"#).hostname == "najaduo.local")
        #expect(try decode(#"{"hashRate":1}"#).hostname == "")
    }

    @Test func derivedMetricsGuardAgainstZeroDivisors() throws {
        let mining = try decode(#"{"power":21.5,"hashRate":1000,"sharesAccepted":99,"sharesRejected":1}"#)
        #expect(mining.efficiencyJoulesPerTerahash == 21.5)
        #expect(mining.rejectedSharePercentage == 1.0)
        let idle = try decode(#"{"power":0,"hashRate":0,"sharesAccepted":0,"sharesRejected":0}"#)
        #expect(idle.efficiencyJoulesPerTerahash == nil)
        #expect(idle.rejectedSharePercentage == nil)
    }

    @Test func unknownKeysNestedStructuresAndArraysSurviveInRaw() throws {
        let info = try decode(#"""
        {"hashRate":500,"vendorFirmwareField":{"nested":[1,2,{"deep":null}]},
         "pools":[{"id":0}],"partitions":[],"showNewBlock":1}
        """#)
        #expect(info.raw["vendorFirmwareField"]?["nested"]?.arrayValue?.count == 3)
        #expect(info.pools.count == 1)
        #expect(info.partitions.isEmpty)
        #expect(info.showNewBlock)   // JSONValue.boolValue coerces numeric 1 to true
    }
}
