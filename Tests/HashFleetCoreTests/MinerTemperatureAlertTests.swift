import Foundation
import Testing
@testable import HashFleetCore

@Suite("Per-miner temperature alert policy")
struct MinerTemperatureAlertTests {
    private let epoch = Date(timeIntervalSince1970: 1_800_000_000)
    private let deviceID = UUID()

    private func sample(
        _ state: inout MinerTemperatureAlertState, _ temperature: Double?, at seconds: TimeInterval = 0,
        nowSeconds: TimeInterval? = nil, online: Bool = true, cached: Bool = false,
        enabled: Bool = true, threshold: Double = 75
    ) throws -> MinerTemperatureAlertEvent? {
        state.observe(
            MinerTemperatureAlertObservation(
                deviceID: deviceID, minerName: "Fixture miner", temperatureCelsius: temperature,
                observedAt: epoch.addingTimeInterval(seconds), isOnline: online, isCached: cached,
                policy: try MinerTemperatureAlertPolicy(isEnabled: enabled, thresholdCelsius: threshold),
                now: epoch.addingTimeInterval(nowSeconds ?? seconds)
            )
        )
    }

    @Test func defaultsAreOptInAndCelsius() {
        let policy = MinerTemperatureAlertPolicy()
        #expect(!policy.isEnabled)
        #expect(policy.thresholdCelsius == 75)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, 29.99, 110.01, -1, 0])
    func rejectsInvalidThreshold(value: Double) {
        #expect(throws: MinerTemperatureAlertPolicy.ValidationError.invalidThreshold) {
            try MinerTemperatureAlertPolicy(isEnabled: true, thresholdCelsius: value)
        }
    }

    @Test(arguments: [30.0, 75.5, 110.0])
    func validThresholdRoundTrips(value: Double) throws {
        let policy = try MinerTemperatureAlertPolicy(isEnabled: true, thresholdCelsius: value)
        #expect(try JSONDecoder().decode(MinerTemperatureAlertPolicy.self,
            from: JSONEncoder().encode(policy)) == policy)
    }

    @Test(arguments: ["{\"isEnabled\":true,\"thresholdCelsius\":900}",
                      "{\"isEnabled\":true,\"thresholdCelsius\":0}",
                      "{\"thresholdCelsius\":75}",
                      "{\"isEnabled\":true,\"thresholdCelsius\":\"NaN\"}"])
    func decodingCannotBypassValidation(json: String) {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(MinerTemperatureAlertPolicy.self, from: Data(json.utf8))
        }
    }

    @Test func firstHotAlertsImmediatelyAtInclusiveThreshold() throws {
        var state = MinerTemperatureAlertState()
        let event = try #require(sample(&state, 75))
        #expect(event.deviceID == deviceID)
        #expect(event.minerName == "Fixture miner")
        #expect(event.temperatureCelsius == 75)
        #expect(event.thresholdCelsius == 75)
        #expect(event.occurredAt == epoch)
        #expect(state.isHotEpisodeActive)
    }

    @Test func disabledAndCoolFirstReadingsDoNotAlert() throws {
        var state = MinerTemperatureAlertState()
        #expect(try sample(&state, 100, enabled: false) == nil)
        #expect(state == MinerTemperatureAlertState())
        #expect(try sample(&state, 74) == nil)
        #expect(try sample(&state, 75, at: 1) != nil)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -1, 0, 150.01])
    func rejectsInvalidReadingsWithoutChangingState(value: Double) throws {
        var state = MinerTemperatureAlertState()
        #expect(try sample(&state, value) == nil)
        #expect(state == MinerTemperatureAlertState())
    }

    @Test func rejectsMissingOfflineCachedStaleAndFutureReadings() throws {
        var state = MinerTemperatureAlertState()
        #expect(try sample(&state, nil) == nil)
        #expect(try sample(&state, 90, online: false) == nil)
        #expect(try sample(&state, 90, cached: true) == nil)
        #expect(try sample(&state, 90, nowSeconds: 120.01) == nil)
        #expect(try sample(&state, 90, at: 1, nowSeconds: 0) == nil)
        #expect(state == MinerTemperatureAlertState())
        #expect(try sample(&state, 90, nowSeconds: 120) != nil)
    }

    @Test func rejectsMissingAndNonfiniteDates() throws {
        let policy = try MinerTemperatureAlertPolicy(isEnabled: true, thresholdCelsius: 75)
        for date in [nil, Date(timeIntervalSinceReferenceDate: .nan), Date(timeIntervalSinceReferenceDate: .infinity)] {
            var state = MinerTemperatureAlertState()
            #expect(state.observe(MinerTemperatureAlertObservation(
                deviceID: deviceID, minerName: "Fixture", temperatureCelsius: 90,
                observedAt: date, isOnline: true, isCached: false, policy: policy, now: epoch
            )) == nil)
            #expect(state == MinerTemperatureAlertState())
        }
        var state = MinerTemperatureAlertState()
        #expect(state.observe(MinerTemperatureAlertObservation(
            deviceID: deviceID, minerName: "Fixture", temperatureCelsius: 90,
            observedAt: epoch, isOnline: true, isCached: false, policy: policy,
            now: Date(timeIntervalSinceReferenceDate: .nan)
        )) == nil)
    }

    @Test func continuouslyHotDoesNotRepeatEvenAfterCooldownOrRestart() throws {
        var state = MinerTemperatureAlertState()
        #expect(try sample(&state, 80) != nil)
        #expect(try sample(&state, 90, at: 1) == nil)
        state = try JSONDecoder().decode(MinerTemperatureAlertState.self, from: JSONEncoder().encode(state))
        #expect(try sample(&state, 100, at: 20_000) == nil)
        #expect(state.lastAlertAt == epoch)
    }

    @Test func hysteresisAndCooldownAreBothRequired() throws {
        var state = MinerTemperatureAlertState()
        #expect(try sample(&state, 80) != nil)
        #expect(try sample(&state, 70.1, at: 1) == nil)
        #expect(state.isHotEpisodeActive)
        #expect(try sample(&state, 70, at: 2) == nil)
        #expect(!state.isHotEpisodeActive)
        #expect(try sample(&state, 80, at: 1799) == nil)
        #expect(try sample(&state, 80, at: 1800) != nil)
        #expect(try sample(&state, 80, at: 4000) == nil)
    }

    @Test func invalidCoolReadingsCannotRearmAndReplayIsRejected() throws {
        var state = MinerTemperatureAlertState()
        #expect(try sample(&state, 80) != nil)
        #expect(try sample(&state, 60, at: 1, online: false) == nil)
        #expect(try sample(&state, 60, at: 2, cached: true) == nil)
        #expect(try sample(&state, 60, at: 3, nowSeconds: 1000) == nil)
        #expect(try sample(&state, 60, at: -1) == nil)
        #expect(try sample(&state, 60) == nil)
        #expect(state.isHotEpisodeActive)
        #expect(try sample(&state, 80, at: 5000) == nil)
    }

    @Test func policyEditsAndClockRollbackNeverBypassCooldown() throws {
        var state = MinerTemperatureAlertState()
        #expect(try sample(&state, 80) != nil)
        state.policyDidChange()
        #expect(try sample(&state, 90, at: 1, threshold: 85) == nil)
        #expect(try sample(&state, 90, at: -1, threshold: 85) == nil)
        #expect(try sample(&state, 90, at: 1800, threshold: 85) != nil)
    }

    @Test func perMinerSuppressionIsIndependent() throws {
        var a = MinerTemperatureAlertState()
        var b = MinerTemperatureAlertState()
        #expect(try sample(&a, 80) != nil)
        #expect(try sample(&a, 80, at: 1) == nil)
        #expect(try sample(&b, 80, at: 1) != nil)
    }

    @Test func corruptHotStateIsRejected() {
        let data = Data("{\"isHotEpisodeActive\":true}".utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(MinerTemperatureAlertState.self, from: data)
        }
    }
}
