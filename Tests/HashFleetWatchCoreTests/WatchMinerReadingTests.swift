import Foundation
import Testing
@testable import HashFleetWatchCore

@Suite struct WatchMinerReadingTests {
    private let id = UUID()
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func reading(at date: Date? = nil) -> WatchMinerReading {
        WatchMinerReading(minerID: id, observedAt: date ?? t0, hashrateGHs: 1)
    }

    @Test func stalenessBoundary() {
        let r = reading()
        #expect(!r.isStale(at: t0))
        #expect(!r.isStale(at: t0.addingTimeInterval(59.9)))
        #expect(!r.isStale(at: t0.addingTimeInterval(60)))
        #expect(r.isStale(at: t0.addingTimeInterval(60.001)))
        #expect(r.isStale(at: t0.addingTimeInterval(3_600)))
    }

    @Test func futureAndInvalidDatesAreStale() {
        let r = reading()
        #expect(!r.isStale(at: t0.addingTimeInterval(-2)))
        #expect(r.isStale(at: t0.addingTimeInterval(-600)))
        #expect(reading(at: Date(timeIntervalSince1970: .infinity)).isStale(at: t0))
        #expect(reading(at: Date(timeIntervalSince1970: .nan)).isStale(at: t0))
        #expect(r.isStale(at: Date(timeIntervalSince1970: .nan)))
    }

    @Test func invalidMetricsBecomeNilNotZero() {
        let r = WatchMinerReading(
            minerID: id, observedAt: t0,
            hashrateGHs: .nan, powerWatts: -1, chipTemperatureC: .infinity,
            vrTemperatureC: -0.5, uptimeSeconds: -10, acceptedShares: -3, rejectedShares: -1
        )
        #expect(r.hashrateGHs == nil)
        #expect(r.powerWatts == nil)
        #expect(r.chipTemperatureC == nil)
        #expect(r.vrTemperatureC == nil)
        #expect(r.uptimeSeconds == nil)
        #expect(r.acceptedShares == nil)
        #expect(r.rejectedShares == nil)
        #expect(r.isMiningPaused == nil)
    }

    @Test func codableRoundTripPreservesTimeAndMetrics() throws {
        let r = WatchMinerReading(
            minerID: id, observedAt: t0, hashrateGHs: 12.5, powerWatts: 9, chipTemperatureC: 55,
            vrTemperatureC: 44, uptimeSeconds: 100, acceptedShares: 5, rejectedShares: 1, isMiningPaused: true
        )
        let decoded = try JSONDecoder().decode(WatchMinerReading.self, from: JSONEncoder().encode(r))
        #expect(decoded == r)
    }

    @Test func decodingDamagedMetricBecomesNilButKeepsOthers() throws {
        let json = #"{"minerID":"\#(id.uuidString)","observedAt":1,"hashrateGHs":"fast","powerWatts":7.5}"#
        let r = try JSONDecoder().decode(WatchMinerReading.self, from: Data(json.utf8))
        #expect(r.hashrateGHs == nil)
        #expect(r.powerWatts == 7.5)
    }

    @Test func decodingWithoutIdentityFails() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(WatchMinerReading.self, from: Data(#"{"observedAt":1}"#.utf8))
        }
    }
}

@Suite struct WatchMinerInfoDecoderTests {
    private let id = UUID()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func decode(_ json: String) throws -> WatchMinerReading {
        try WatchMinerInfoDecoder.reading(from: Data(json.utf8), minerID: id, observedAt: now)
    }

    @Test func decodesFullPayload() throws {
        let r = try decode("""
        {"hashRate":1020.5,"power":14.2,"temp":58.5,"temp2":60.1,"vrTemp":49,"uptimeSeconds":93600,
         "sharesAccepted":1204,"sharesRejected":3,"miningPaused":false}
        """)
        #expect(r.minerID == id)
        #expect(r.observedAt == now)
        #expect(r.hashrateGHs == 1020.5)
        #expect(r.powerWatts == 14.2)
        #expect(r.chipTemperatureC == 60.1)
        #expect(r.vrTemperatureC == 49)
        #expect(r.uptimeSeconds == 93_600)
        #expect(r.acceptedShares == 1_204)
        #expect(r.rejectedShares == 3)
        #expect(r.isMiningPaused == false)
    }

    @Test func missingFieldsAreNilNeverZero() throws {
        let r = try decode(#"{"hashRate":10}"#)
        #expect(r.hashrateGHs == 10)
        #expect(r.powerWatts == nil)
        #expect(r.chipTemperatureC == nil)
        #expect(r.vrTemperatureC == nil)
        #expect(r.uptimeSeconds == nil)
        #expect(r.acceptedShares == nil)
        #expect(r.isMiningPaused == nil)
    }

    @Test func negativeSentinelTemperaturesAreIgnored() throws {
        let r = try decode(#"{"hashRate":1,"temp":-1,"temp2":-1,"vrTemp":-1}"#)
        #expect(r.chipTemperatureC == nil)
        #expect(r.vrTemperatureC == nil)
        let one = try decode(#"{"hashRate":1,"temp":-1,"temp2":61}"#)
        #expect(one.chipTemperatureC == 61)
    }

    @Test func implausibleTemperaturesAreIgnored() throws {
        let r = try decode(#"{"hashRate":1,"temp":9999,"temp2":55,"vrTemp":1e9}"#)
        #expect(r.chipTemperatureC == 55)
        #expect(r.vrTemperatureC == nil)
    }

    @Test func maximumValidTempWins() throws {
        #expect(try decode(#"{"hashRate":1,"temp":70,"temp2":65}"#).chipTemperatureC == 70)
    }

    @Test func wrongTypesBecomeNotReported() throws {
        let r = try decode(#"{"hashRate":"12","power":true,"temp":[1],"uptimeSeconds":null,"sharesAccepted":"5","sharesRejected":2.5,"miningPaused":"yes","vrTemp":55}"#)
        #expect(r.hashrateGHs == nil)
        #expect(r.powerWatts == nil)
        #expect(r.chipTemperatureC == nil)
        #expect(r.uptimeSeconds == nil)
        #expect(r.acceptedShares == nil)
        #expect(r.rejectedShares == nil)
        #expect(r.isMiningPaused == nil)
        #expect(r.vrTemperatureC == 55)
    }

    @Test func nonfiniteAndNegativeValuesAreRejected() throws {
        let r = try decode(#"{"hashRate":-5,"power":1e999,"vrTemp":40}"#)
        #expect(r.hashrateGHs == nil)
        #expect(r.powerWatts == nil)
    }

    @Test func numericPausedFlag() throws {
        #expect(try decode(#"{"hashRate":1,"miningPaused":1}"#).isMiningPaused == true)
        #expect(try decode(#"{"hashRate":1,"miningPaused":0}"#).isMiningPaused == false)
        #expect(try decode(#"{"hashRate":1,"miningPaused":7}"#).isMiningPaused == nil)
    }

    @Test(arguments: ["", "not json", "[]", "[1,2]", "null", "42", "\"text\"", "{}", #"{"unrelated":1}"#, #"{"hashRate":"x"}"#])
    func rejectsNonMinerPayloads(json: String) {
        #expect(throws: WatchMinerFetchError.invalidResponse) { try decode(json) }
    }

    @Test func privateFieldsNeverEnterTheModel() throws {
        let r = try decode("""
        {"hashRate":1,"stratumUser":"bc1qsecretwalletaddress.worker","stratumPassword":"hunter2",
         "ssid":"HomeWifi","wifiPassword":"wifisecret","macAddr":"AA:BB:CC:DD:EE:FF","hostname":"bitaxe"}
        """)
        let encoded = try #require(String(bytes: JSONEncoder().encode(r), encoding: .utf8))
        for secret in ["bc1q", "hunter2", "HomeWifi", "wifisecret", "AA:BB", "bitaxe", "stratum", "ssid"] {
            #expect(!encoded.contains(secret))
        }
    }
}
