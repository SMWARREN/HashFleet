import XCTest
@testable import HashFleetCore

/// Behavior coverage for Core utilities: `MinerPowerAlertState.observe` (episode lifecycle +
/// suppression guards), `MinerPowerAlertPolicy` decoding/validation, `FleetBlockDetection.detect`
/// (reboot-guarded block announcements), `FleetSharedStore.BlockBaseline(info:)` capture and
/// isolated announcement defaults APIs, and `JSONRedactor`.
///
/// The store's `writeDevices`/`readDevices` entry points resolve the real App Group suite
/// with no injection seam, so these tests never call them and never touch the shared
/// container. Baseline capture and announcement state use production APIs with isolated defaults.
final class CoreUtilitiesCoverageTests: XCTestCase {

    // MARK: - MinerPowerAlertState.observe

    private func observation(
        deviceID: UUID = UUID(),
        name: String = "Gamma 602",
        watts: Double?,
        observedAt: Date,
        isOnline: Bool = true,
        isCached: Bool = false,
        policy: MinerPowerAlertPolicy,
        now: Date
    ) -> MinerPowerAlertObservation {
        MinerPowerAlertObservation(
            deviceID: deviceID, minerName: name, watts: watts, observedAt: observedAt,
            isOnline: isOnline, isCached: isCached, policy: policy, now: now
        )
    }

    private func enabledPolicy(threshold: Double = 100) throws -> MinerPowerAlertPolicy {
        try MinerPowerAlertPolicy(isEnabled: true, thresholdWatts: threshold)
    }

    func testObserveAlertsOncePerHighEpisodeThenResolvesBelowHysteresis() throws {
        let policy = try enabledPolicy()
        var state = MinerPowerAlertState()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        // A fresh high reading alerts immediately.
        let exceeded = state.observe(
            observation(watts: 120, observedAt: now, policy: policy, now: now)
        )
        XCTAssertEqual(exceeded?.kind, .exceeded)
        XCTAssertEqual(exceeded?.watts, 120)
        XCTAssertEqual(exceeded?.minerName, "Gamma 602")

        // The same episode does not re-alert while it stays high.
        XCTAssertNil(
            state.observe(observation(watts: 121, observedAt: now.addingTimeInterval(10),
                                      policy: policy, now: now.addingTimeInterval(10)))
        )

        // A reading merely under the threshold (but within hysteresis) neither alerts nor resolves.
        XCTAssertNil(
            state.observe(observation(watts: 97, observedAt: now.addingTimeInterval(20),
                                      policy: policy, now: now.addingTimeInterval(20)))
        )

        // Dropping at least hysteresisWatts below the threshold resolves the episode.
        let resolved = state.observe(
            observation(watts: 95, observedAt: now.addingTimeInterval(30),
                        policy: policy, now: now.addingTimeInterval(30))
        )
        XCTAssertEqual(resolved?.kind, .resolved)
        XCTAssertEqual(resolved?.thresholdWatts, 100)

        // After resolution a new high reading respects the 30-minute alert cooldown.
        XCTAssertNil(
            state.observe(observation(watts: 150, observedAt: now.addingTimeInterval(40),
                                      policy: policy, now: now.addingTimeInterval(40)))
        )
        let afterCooldown = now.addingTimeInterval(MinerPowerAlertPolicy.cooldown + 60)
        let realert = state.observe(
            observation(watts: 150, observedAt: afterCooldown, policy: policy, now: afterCooldown)
        )
        XCTAssertEqual(realert?.kind, .exceeded)
    }

    func testObserveSuppressionsNeverAlertOrMutateTheEpisode() throws {
        let policy = try enabledPolicy()
        var state = MinerPowerAlertState()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        // Disabled policy, offline, cached, missing watts, negative, over-range and
        // NaN readings are all ignored before the episode state is touched.
        XCTAssertNil(state.observe(observation(watts: 900, observedAt: now,
            policy: MinerPowerAlertPolicy(), now: now)))
        XCTAssertNil(state.observe(observation(watts: 900, observedAt: now,
            isOnline: false, policy: policy, now: now)))
        XCTAssertNil(state.observe(observation(watts: 900, observedAt: now,
            isCached: true, policy: policy, now: now)))
        XCTAssertNil(state.observe(observation(watts: nil, observedAt: now,
            policy: policy, now: now)))
        XCTAssertNil(state.observe(observation(watts: -1, observedAt: now,
            policy: policy, now: now)))
        XCTAssertNil(state.observe(observation(watts: 10_001, observedAt: now,
            policy: policy, now: now)))
        XCTAssertNil(state.observe(observation(watts: .nan, observedAt: now,
            policy: policy, now: now)))
        XCTAssertFalse(state.isHighEpisodeActive)
        XCTAssertNil(state.lastObservedAt)

        // A stale (> maximumReadingAge) or future-dated reading is rejected too.
        let stale = now.addingTimeInterval(-(MinerPowerAlertPolicy.maximumReadingAge + 1))
        XCTAssertNil(state.observe(observation(watts: 900, observedAt: stale,
            policy: policy, now: now)))
        XCTAssertNil(state.observe(observation(watts: 900,
            observedAt: now.addingTimeInterval(60), policy: policy, now: now)))

        // An out-of-order reading (older than the last observed one) is dropped.
        let first = now.addingTimeInterval(100)
        XCTAssertNotNil(state.observe(observation(watts: 900, observedAt: first,
            policy: policy, now: first)))
        XCTAssertNil(state.observe(observation(watts: 900, observedAt: first,
            policy: policy, now: first)))
    }

    func testPolicyEditingResetsTheEpisodeButKeepsTheCooldown() throws {
        let policy = try enabledPolicy()
        var state = MinerPowerAlertState()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertNotNil(state.observe(observation(watts: 900, observedAt: now,
            policy: policy, now: now)))
        state.policyDidChange()
        XCTAssertFalse(state.isHighEpisodeActive)

        // Editing a policy reopens episodes but never bypasses the alert cooldown.
        XCTAssertNil(state.observe(observation(watts: 900,
            observedAt: now.addingTimeInterval(60), policy: policy,
            now: now.addingTimeInterval(60))))
    }

    func testStateRoundTripsAndRejectsCorruptedSuppressionState() throws {
        var state = MinerPowerAlertState()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let policy = try enabledPolicy()
        _ = state.observe(observation(watts: 900, observedAt: now, policy: policy, now: now))

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(MinerPowerAlertState.self, from: data)
        XCTAssertEqual(decoded, state)

        // An active episode without a recorded alert timestamp is corrupt and rejected.
        let corrupt = """
        {"isHighEpisodeActive": true, "lastObservedAt": 700000000.0}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(
            MinerPowerAlertState.self, from: Data(corrupt.utf8)
        ))
    }

    // MARK: - MinerPowerAlertPolicy

    func testPolicyValidationAndDecoding() throws {
        XCTAssertThrowsError(try MinerPowerAlertPolicy(isEnabled: true, thresholdWatts: 0))
        XCTAssertThrowsError(try MinerPowerAlertPolicy(isEnabled: true, thresholdWatts: 5_001))
        XCTAssertThrowsError(try MinerPowerAlertPolicy(isEnabled: true, thresholdWatts: .infinity))

        let valid = try XCTUnwrap(try? MinerPowerAlertPolicy(isEnabled: true, thresholdWatts: 250))
        XCTAssertTrue(valid.isEnabled)
        XCTAssertEqual(valid.thresholdWatts, 250)
        XCTAssertEqual(MinerPowerAlertPolicy().isEnabled, false)
        XCTAssertEqual(MinerPowerAlertPolicy().thresholdWatts, MinerPowerAlertPolicy.defaultThresholdWatts)

        // Out-of-range thresholds are rejected at decode time as well.
        let bad = Data("{\"isEnabled\": true, \"thresholdWatts\": 9999}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(MinerPowerAlertPolicy.self, from: bad))
    }

    // MARK: - FleetBlockDetection

    private func blockInfo(
        blockFound: Int?, showNewBlock: Bool, uptimeSeconds: Int?, blockHeight: Int? = nil
    ) -> MinerInfo {
        var raw: [String: JSONValue] = [:]
        if let blockFound { raw["blockFound"] = .integer(Int64(blockFound)) }
        if showNewBlock { raw["showNewBlock"] = .bool(true) }
        if let uptimeSeconds { raw["uptimeSeconds"] = .integer(Int64(uptimeSeconds)) }
        if let blockHeight { raw["blockHeight"] = .integer(Int64(blockHeight)) }
        return MinerInfo(raw: raw)
    }

    func testBlockDetectionIsSilentOnFirstObservation() {
        XCTAssertNil(FleetBlockDetection.detect(
            previous: nil,
            current: blockInfo(blockFound: 3, showNewBlock: false, uptimeSeconds: 500)
        ))
    }

    func testBlockDetectionFiresOnRisingCounterWithoutReboot() throws {
        let previous = FleetSharedStore.BlockBaseline(
            count: 2, showNewBlock: false, uptimeSeconds: 1_000
        )
        let current = blockInfo(
            blockFound: 3, showNewBlock: false, uptimeSeconds: 2_000, blockHeight: 849_123
        )
        let result = try XCTUnwrap(FleetBlockDetection.detect(previous: previous, current: current))
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.height, 849_123)
        XCTAssertNil(result.coinLabel)
    }

    func testBlockDetectionIgnoresCounterClimbAcrossReboot() {
        let previous = FleetSharedStore.BlockBaseline(
            count: 2, showNewBlock: false, uptimeSeconds: 5_000
        )
        // Firmware counters restart from zero after a reboot and re-climb; a counter
        // increase that coincides with an uptime decrease is a power cycle, not a solve.
        let rebooted = blockInfo(blockFound: 3, showNewBlock: false, uptimeSeconds: 100)
        XCTAssertNil(FleetBlockDetection.detect(previous: previous, current: rebooted))
    }

    func testBlockDetectionFiresWhenFirmwareFlagRaisesAndLabelsTheActivePoolCoin() {
        let previous = FleetSharedStore.BlockBaseline(count: 7, showNewBlock: false, uptimeSeconds: 10)
        // ckpool slots keep the wallet in the separate `user` field; embedded credentials
        // would make extractHost reject the URL entirely. Any documented ckpool host infers
        // BTC from the host alone. Fixture wallet is synthetic and fails BTC validation,
        // which must not stop the coin label from being reported.
        let poolRow: [String: JSONValue] = [
            "id": .integer(0),
            "url": .string("stratum+tcp://stratum.ckpool.org:3333"),
            "user": .string("bc1qfixture-not-a-real-wallet")
        ]
        let info = MinerInfo(raw: [
            "blockFound": .integer(7),
            "showNewBlock": .bool(true),
            "uptimeSeconds": .integer(20),
            "blockHeight": .integer(855_000),
            "pools": .array([.object(poolRow)])
        ])
        let result = FleetBlockDetection.detect(previous: previous, current: info)
        XCTAssertEqual(result?.coinLabel, "BTC")
        XCTAssertEqual(result?.height, 855_000)
        XCTAssertEqual(result?.count, 7)
    }

    // MARK: - FleetSharedStore baseline and isolated defaults APIs

    func testBlockBaselineCaptureAndIsolatedAnnouncementDefaults() throws {
        let info = MinerInfo(raw: [
            "blockFound": .integer(4),
            "showNewBlock": .bool(true),
            "uptimeSeconds": .integer(3_600)
        ])
        let baseline = FleetSharedStore.BlockBaseline(info: info)
        XCTAssertEqual(baseline.count, 4)
        XCTAssertTrue(baseline.showNewBlock)
        XCTAssertEqual(baseline.uptimeSeconds, 3_600)

        let empty = FleetSharedStore.BlockBaseline(info: MinerInfo(raw: [:]))
        XCTAssertNil(empty.count)
        XCTAssertFalse(empty.showNewBlock)
        XCTAssertNil(empty.uptimeSeconds)

        // Inject a unique defaults suite so these production APIs never touch the real App Group.
        let suiteName = "CoreUtilitiesCoverageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        FleetSharedStore.markAppActive(true, now: now, defaults: defaults)
        XCTAssertTrue(FleetSharedStore.isAppActive(now: now, defaults: defaults))
        XCTAssertFalse(FleetSharedStore.isAppActive(
            now: now.addingTimeInterval(FleetSharedStore.appActiveHeartbeat), defaults: defaults))
        FleetSharedStore.markAppActive(false, now: now, defaults: defaults)
        XCTAssertFalse(FleetSharedStore.isAppActive(now: now, defaults: defaults))

        let key = FleetSharedStore.blockKey(
            deviceID: UUID(), count: baseline.count, height: 123, uptimeSeconds: baseline.uptimeSeconds
        )
        XCTAssertTrue(FleetSharedStore.claimBlockAnnouncement(key, defaults: defaults))
        XCTAssertFalse(FleetSharedStore.claimBlockAnnouncement(key, defaults: defaults))
    }

    // MARK: - JSONRedactor

    func testJSONRedactorHidesSensitiveKeysAtEveryDepthAndKeepsFallback() throws {
        let request = """
        {"user": "example-user", "password": "hunter2", "pools": [
            {"url": "stratum+tcp://x@stratum.ckpool.org:3333",
             "apiKey": "abcd1234", "nested": {"AUTHORIZATION": "Bearer t"}}
        ]}
        """
        let pretty = JSONRedactor.prettyString(from: Data(request.utf8))
        XCTAssertFalse(pretty.contains("hunter2"))
        XCTAssertFalse(pretty.contains("abcd1234"))
        XCTAssertFalse(prettyContainsBearerToken(pretty))
        XCTAssertTrue(pretty.contains("•••••• (will be sent)"))
        XCTAssertTrue(pretty.contains("stratum.ckpool.org"))

        // Non-JSON data falls back to the provided label rather than crashing.
        XCTAssertEqual(JSONRedactor.prettyString(from: Data([0xFF, 0xFE]), fallback: "raw bytes"), "raw bytes")

        // Redaction recurses through dictionaries and arrays while leaving other values alone.
        let redacted = JSONRedactor.redacted([
            "WiFiPass": "wifi-secret", "safe": 42, "list": [["token": "t1", "ok": "yes"]]
        ] as [String: Any]) as? [String: Any]
        XCTAssertEqual((redacted?["safe"] as? Int), 42)
        XCTAssertEqual((redacted?["WiFiPass"] as? String), "•••••• (will be sent)")
        let inner = ((redacted?["list"] as? [Any])?.first as? [String: Any])
        XCTAssertEqual(inner?["ok"] as? String, "yes")
        XCTAssertEqual(inner?["token"] as? String, "•••••• (will be sent)")
    }

    private func prettyContainsBearerToken(_ text: String) -> Bool {
        text.contains("Bearer t")
    }
}
