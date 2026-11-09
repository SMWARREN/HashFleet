import Foundation
import Testing
@testable import HashFleetCore

struct MinerFirmwareTelemetryTests {
    private func info(_ domains: [[JSONValue]], expected: JSONValue? = .integer(1600)) -> MinerInfo {
        var raw: [String: JSONValue] = ["hashrateMonitor": .object(["asics": .array(domains.map {
            .object(["domains": .array($0)])
        })])]
        raw["expectedHashrate"] = expected
        return MinerInfo(raw: raw)
    }

    @Test(arguments: [4, 8])
    func completeDomainGeometryHasStableIndicesAndReportedNominal(count: Int) {
        let result = info([Array(repeating: .integer(100), count: count),
                           Array(repeating: .string("101.5"), count: count)]).hashrateDomains
        #expect(result.count == count * 2)
        #expect(Set(result.map(\.id)).count == count * 2)
        #expect(result.first?.id == "0:0")
        #expect(result.last?.id == "1:\(count - 1)")
        #expect(result.last?.hashrateGHs == 101.5)
        #expect(result.allSatisfy { $0.nominalHashrateGHs == 1600 / Double(count * 2) })
    }

    @Test(arguments: [JSONValue.bool(true), .integer(-1), .number(.infinity), .number(.nan), .string("NaN"), .null])
    func malformedDomainNeverBecomesAZeroOrAFalseNominal(value: JSONValue) {
        #expect(info([[.integer(100), value]]).hashrateDomains.isEmpty)
    }

    @Test func missingMalformedAndOversizedGeometryIsUnavailable() {
        #expect(MinerInfo(raw: [:]).hashrateDomains.isEmpty)
        #expect(info([]).hashrateDomains.isEmpty)
        #expect(info([[]]).hashrateDomains.isEmpty)
        #expect(info([Array(repeating: .integer(1), count: 65)]).hashrateDomains.isEmpty)
        #expect(info(Array(repeating: [.integer(1)], count: 65)).hashrateDomains.isEmpty)
        #expect(info(Array(repeating: Array(repeating: .integer(1), count: 64), count: 64)).hashrateDomains.isEmpty)
        #expect(info([[.integer(0)]], expected: nil).hashrateDomains.first?.hashrateGHs == 0)
        #expect(info([[.integer(0)]], expected: nil).hashrateDomains.first?.nominalHashrateGHs == nil)
        #expect(info([[.integer(1)]], expected: .integer(0)).hashrateDomains.first?.nominalHashrateGHs == nil)
    }

    private func pools(fallback: JSONValue = .integer(0), active: JSONValue? = nil) -> MinerInfo {
        var raw: [String: JSONValue] = ["primaryPoolIndex": .integer(5), "secondaryPoolIndex": .integer(2),
            "isUsingFallbackStratum": fallback,
            "pools": .array([
                .object(["id": .integer(2), "stratumTLS": .integer(0), "stratumProtocol": .string("SV1")]),
                .object(["id": .integer(5), "stratumTLS": .integer(2), "stratumProtocol": .string("SV1")])
            ])]
        raw["activePoolIndex"] = active
        return MinerInfo(raw: raw)
    }

    @Test func routingUsesPersistentSlotIdentityRatherThanArrayOrder() {
        #expect(MinerPoolDiagnostics(info: pools()).transportLabel == "TLS configured (custom certificate)")
        #expect(MinerPoolDiagnostics(info: pools(fallback: .integer(1))).transportLabel == "TLS disabled in active-pool configuration")
        #expect(MinerPoolDiagnostics(info: pools(fallback: .integer(1), active: .integer(5))).transportLabel == "TLS configured (custom certificate)")
        #expect(MinerPoolDiagnostics(info: pools(active: .integer(7))).transportLabel == "Transport not reported")
        #expect(MinerPoolDiagnostics(info: pools(active: .bool(false))).transportLabel == "Transport not reported")
        #expect(MinerPoolDiagnostics(info: pools(fallback: .integer(3))).usingFallback == nil)
        #expect(MinerPoolDiagnostics(info: pools(fallback: .bool(true))).usingFallback == true)
    }

    @Test(arguments: [JSONValue.array([]), .string("bad"), .array([
        .object(["id": .integer(5), "stratumTLS": .integer(2)]),
        .object(["id": .integer(5), "stratumTLS": .integer(0)])
    ]), .array([.object(["id": .bool(false), "stratumTLS": .integer(2)])])])
    func malformedPoolTableNeverFallsBackToLegacySecurity(value: JSONValue) {
        var valueInfo = pools()
        valueInfo.raw["pools"] = value
        valueInfo.raw["stratumTLS"] = .integer(2)
        #expect(MinerPoolDiagnostics(info: valueInfo).transportLabel == "Transport not reported")
    }

    @Test func legacyTLSNeedsExplicitRoutingAndV2IsNotMislabeledPlaintext() {
        var legacy = MinerInfo(raw: ["stratumTLS": .integer(1), "fallbackStratumTLS": .integer(0)])
        #expect(MinerPoolDiagnostics(info: legacy).transportLabel == "Transport not reported")
        legacy.raw["isUsingFallbackStratum"] = .integer(0)
        #expect(MinerPoolDiagnostics(info: legacy).transportLabel == "TLS configured (bundled certificates)")
        legacy.raw["isUsingFallbackStratum"] = .integer(1)
        #expect(MinerPoolDiagnostics(info: legacy).transportLabel == "TLS disabled in active-pool configuration")
        legacy.raw["fallbackStratumProtocol"] = .string("SV2")
        #expect(MinerPoolDiagnostics(info: legacy).transportLabel == "Stratum V2 configured (transport unverified)")
        legacy.raw["fallbackStratumProtocol"] = .bool(true)
        #expect(MinerPoolDiagnostics(info: legacy).transportLabel == "Transport not reported")
        legacy.raw["activePoolIndex"] = .integer(0)
        #expect(MinerPoolDiagnostics(info: legacy).transportLabel == "Transport not reported")
    }

    @Test func poolMessagesAreBoundedControlStrippedAndSecretRedacted() throws {
        let secret = "fixture-wallet-value-not-for-display"
        let info = MinerInfo(raw: ["stratumUser": .string(secret), "stratumPassword": .string("private-pass"),
            "primaryPoolError": .string("Denied \(secret) private-pass\n\u{001B}[31m https://user:pass@fixture.invalid/path"),
            "poolBanner": .string("Welcome \u{202E}" + String(repeating: "a", count: 30))])
        let diagnostics = MinerPoolDiagnostics(info: info)
        let error = try #require(diagnostics.primaryError)
        #expect(error.contains(secret) == false)
        #expect(error.contains("private-pass") == false)
        #expect(error.contains("user:pass") == false)
        #expect(error.contains("\n") == false)
        #expect(error.contains("\u{001B}") == false)
        #expect(diagnostics.banner?.contains("\u{202E}") == false)
        #expect(diagnostics.banner?.contains(String(repeating: "a", count: 30)) == false)
        #expect(MinerPoolDiagnostics(info: MinerInfo(raw: ["poolBanner": .string(" \n")])).banner == nil)
        #expect(MinerPoolDiagnostics(info: MinerInfo(raw: ["poolBanner": .string(String(repeating: "x", count: 5000))])).banner == "Message omitted (too long)")
        let bounded = MinerPoolDiagnostics(info: MinerInfo(raw: ["poolBanner": .string(String(repeating: "word ", count: 100))]))
        #expect(bounded.banner?.count == 240)
    }

    @Test func computedTelemetryDoesNotChangeRawJSONSchema() throws {
        let original = info([[.integer(1), .integer(2)]])
        _ = original.hashrateDomains
        _ = MinerPoolDiagnostics(info: original)
        let decoded = try JSONDecoder().decode(MinerInfo.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(decoded.raw["hashrateDomains"] == nil)
        #expect(decoded.raw["transportLabel"] == nil)
    }
}
