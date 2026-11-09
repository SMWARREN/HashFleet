import Foundation
import Testing
@testable import HashFleetWatchCore

@Suite struct WatchDiscoveryIdentificationTests {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    // MARK: ASICModel gate

    @Test(arguments: ["BM1370", "BM1366", "BM1397", "bm1368", "BM1", "BM01"])
    func acceptsValidBMModels(model: String) {
        #expect(WatchDiscoveryIdentification.isValidASICModel(model))
    }

    @Test(arguments: [
        "", "BM", "bm", "B1370",        // too short / missing digits
        "BM1370X", "BM13-70", "BM13.7", // trailing non-digits
        "XBM1370", "1370", "ABCD",      // wrong prefix
        "BM1370\u{0007}"                // control char
    ])
    func rejectsInvalidModels(model: String) {
        #expect(!WatchDiscoveryIdentification.isValidASICModel(model))
    }

    @Test func rejectsOversizeModel() {
        #expect(!WatchDiscoveryIdentification.isValidASICModel("BM" + String(repeating: "1", count: 64)))
    }

    @Test func rejectsNilModel() {
        #expect(!WatchDiscoveryIdentification.isValidASICModel(nil))
    }

    // MARK: Positive identification

    @Test func identifiesRealNajaCompositeASICModel() {
        // Sanitized actual API shape, not a fabricated single-chip model for a dual-model board.
        let name = WatchDiscoveryIdentification.minerName(
            from: data(#"{"ASICModel":"BM1372/BM1373","hashRate":9000,"hostname":"workshop-duo"}"#)
        )
        #expect(name == "workshop-duo")
    }

    @Test(arguments: ["BM1372/", "/BM1373", "BM1372/other", "BM1372/BM1373/BC1", "BM1372/BM1373/BM1370", "BM1372//BM1373"])
    func rejectsMalformedCompositeASICModels(model: String) {
        #expect(!WatchDiscoveryIdentification.isValidASICModel(model))
    }

    @Test func identifiesGenuineMinerAndUsesHostname() {
        let name = WatchDiscoveryIdentification.minerName(
            from: data(#"{"ASICModel":"BM1370","hashRate":500,"hostname":"gamma-602"}"#)
        )
        #expect(name == "gamma-602")
    }

    @Test func fallsBackThroughAllowlistedNameKeys() {
        // No hostname, but a deviceName is present.
        let name = WatchDiscoveryIdentification.minerName(
            from: data(#"{"ASICModel":"BM1370","power":12,"deviceName":"Bench Miner"}"#)
        )
        #expect(name == "Bench Miner")
    }

    @Test func usesFallbackNameWhenNoAllowlistedNameValid() {
        let name = WatchDiscoveryIdentification.minerName(
            from: data(#"{"ASICModel":"BM1370","hashRate":500,"hostname":""}"#)
        )
        #expect(name == WatchDiscoveryIdentification.fallbackName)
    }

    @Test func lowercaseAsicModelKeyAlsoWorks() {
        let name = WatchDiscoveryIdentification.minerName(
            from: data(#"{"asicModel":"BM1368","temp":55,"hostname":"duo"}"#)
        )
        #expect(name == "duo")
    }

    // MARK: Negatives

    @Test func rejectsWhenModelMissing() {
        #expect(WatchDiscoveryIdentification.minerName(from: data(#"{"hashRate":500,"hostname":"x"}"#)) == nil)
    }

    @Test func rejectsWhenModelPresentButNoValidMetric() {
        // Valid model shape, but every metric is wrong-typed, so no telemetry => not a miner.
        let json = #"{"ASICModel":"BM1370","hashRate":"fast","power":"x","temp":"y","hostname":"x"}"#
        #expect(WatchDiscoveryIdentification.minerName(from: data(json)) == nil)
    }

    @Test(arguments: [
        "<html>login</html>",
        "not json",
        "[]",
        "{}",
        #"{"unrelated":1}"#,
        #"{"ASICModel":1370,"hashRate":5}"#,    // wrong-typed model
        #"{"ASICModel":true,"hashRate":5}"#
    ])
    func rejectsNonMinerOrHostilePayloads(json: String) {
        #expect(WatchDiscoveryIdentification.minerName(from: data(json)) == nil)
    }

    // MARK: Name sanitization

    @Test func sanitizesControlCharactersAndTrims() {
        let name = WatchDiscoveryIdentification.minerName(
            from: data(#"{"ASICModel":"BM1370","hashRate":1,"hostname":"  mi\u0007ner\n  "}"#)
        )
        #expect(name == "miner")
    }

    @Test func truncatesOverlongName() {
        let long = String(repeating: "a", count: 80)
        let name = WatchDiscoveryIdentification.minerName(
            from: data(#"{"ASICModel":"BM1370","hashRate":1,"hostname":"\#(long)"}"#)
        )
        #expect(name?.count == WatchFleetLimits.maximumNameLength)
    }

    @Test func controlOnlyNameFallsThroughToFallback() {
        let name = WatchDiscoveryIdentification.minerName(
            from: data(#"{"ASICModel":"BM1370","hashRate":1,"hostname":"\u0007\u0007"}"#)
        )
        #expect(name == WatchDiscoveryIdentification.fallbackName)
    }

    // MARK: Secrets never used as names

    @Test func neverUsesSecretBearingKeysForName() {
        // stratumUser/ssid/wifiPassword/macAddr are not allow-listed; name must fall back, not leak them.
        let json = #"""
        {"ASICModel":"BM1370","hashRate":1,
         "stratumUser":"bc1qsecretwallet.worker","ssid":"HomeWifi","wifiPassword":"hunter2",
         "macAddr":"AA:BB:CC:DD:EE:FF"}
        """#
        let name = WatchDiscoveryIdentification.minerName(from: data(json))
        #expect(name == WatchDiscoveryIdentification.fallbackName)
        if let name {
            for secret in ["bc1q", "HomeWifi", "hunter2", "AA:BB"] {
                #expect(!name.contains(secret))
            }
        }
    }
}
