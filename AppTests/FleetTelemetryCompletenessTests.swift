import Foundation
import Testing
import HashFleetCore
import GRDB
@testable import HashFleet

/// Telemetry completeness: a valid firmware response is not a promise that every metric is present.
///
/// The invariants under test:
/// - A metric no online miner reported is absent, never a fabricated zero total.
/// - A metric only some online miners reported is a subtotal that reports its own coverage.
/// - Efficiency uses only miners that reported hashrate and power together.
/// - `glance` fails closed to `.empty` whenever a reading is incomplete, because the shared payload
///   has no completeness field and a widget would render a subtotal as the whole fleet.
/// - Offline miners are excluded exactly as before, and history never gains a fabricated point.
///
/// HTTP-encodable fixtures exercise the actual poll path through isolated URLProtocol transport.
/// Non-finite values use the pure aggregate type because JSON cannot represent NaN or infinity.
@Suite(.serialized) @MainActor
struct FleetTelemetryCompletenessTests {
    @Test func recorderUsesCanonicalFieldsAndPreservesRealZero() async throws {
        let info = MinerInfo(raw: [
            "hashRate": .integer(0), "power": .integer(0), "temp": .integer(-1),
            "fanspeed": .integer(0), "fanrpm": .integer(3200), "fan": .integer(99),
            "sharesAccepted": .integer(42), "sharesRejected": .integer(0),
            "uptimeSeconds": .integer(120), "activePoolIndex": .integer(3),
            "isUsingFallbackStratum": .bool(true)
        ])
        let input = FleetStore.telemetryReading(info: info)
        #expect(input.hashrate == 0 && input.power == 0 && input.temp == nil)
        #expect(input.fanSpeed == 0 && input.fanRPM == 3200)
        #expect(input.sharesAccepted == 42 && input.sharesRejected == 0)
        #expect(input.uptimeSeconds == 120 && input.activePoolIndex == 3 && input.isFallbackPool == true)

        // Exercise the exact conversion used by the app recorder through a disposable SQLite DB.
        let queue = try DatabaseQueue()
        let database = MinerTelemetryDatabase(databaseQueue: queue)
        database.recordReading(minerId: "fixture", reading: input)
        await database.flushReadings()
        let values = try await queue.read { db -> [Int?] in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM miner_readings WHERE miner_id = ?", arguments: ["fixture"])
            else { return [] }
            return ["hashrate", "power", "temp", "fan_speed", "fan_rpm", "shares_accepted",
                    "shares_rejected", "uptime_seconds", "active_pool_index", "is_fallback_pool"]
                .map { row[$0] as Int? }
        }
        #expect(values == [0, 0, nil, 0, 3200, 42, 0, 120, 3, 1])
    }

    @Test func recorderDoesNotGuessAbsentMetricsOrPoolRoles() {
        for value: JSONValue in [.null, .bool(false), .string("bad"), .integer(-1)] {
            let input = FleetStore.telemetryReading(info: MinerInfo(raw: [
                "hashRate": value, "power": value, "fanspeed": value, "sharesAccepted": value,
                "activePoolIndex": .integer(1)
            ]))
            #expect(input.hashrate == nil && input.power == nil && input.fanSpeed == nil)
            #expect(input.sharesAccepted == nil && input.sharesRejected == nil && input.uptimeSeconds == nil)
            #expect(input.activePoolIndex == 1 && input.isFallbackPool == nil)
        }
        let translatedCPU = FleetStore.telemetryReading(info: MinerInfo(raw: [
            "hashRate": .number(0), "sharesAccepted": .integer(0), "sharesRejected": .integer(0),
            "uptimeSeconds": .integer(0), "miningPaused": .bool(true)
        ]))
        #expect(translatedCPU.hashrate == 0 && translatedCPU.sharesAccepted == 0)
        #expect(translatedCPU.power == nil && translatedCPU.temp == nil && translatedCPU.fanSpeed == nil)
    }

    @Test func releaseProjectionHidesCPUWithoutDeletingItsSavedConfiguration() throws {
        let suite = "app.hashfleet.release-projection.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let esp = MinerDevice(name: "ESP", address: "esp.invalid")
        let cpu = MinerDevice(name: "CPU", address: "cpu.invalid", kind: .xmrig)
        let saved = try JSONEncoder().encode([esp, cpu])
        defaults.set(saved, forKey: FleetStore.storageKey)
        let store = FleetStore(defaults: defaults)
        #expect(!FleetReleaseFeatures.xmrigEnabled)
        #expect(store.visibleDevices == [esp])
        #expect(store.devices == [esp, cpu])
        #expect(defaults.data(forKey: FleetStore.storageKey) == saved)
        #expect(FleetHistoryKind.available(in: store.visibleDevices) == [.sha256])
        #expect(FleetReleaseFeatures.visibleDevices(store.devices, xmrigEnabled: true) == [esp, cpu])
        #expect(FleetHistoryKind.available(in: FleetReleaseFeatures.visibleDevices(store.devices, xmrigEnabled: true)) == [.sha256, .cpu])
    }
    // MARK: - Fixtures

    struct CompletenessFixture {
        let store: FleetStore
        let defaults: UserDefaults
        let suite: String
    }

    func store(_ payloads: [[String: JSONValue]?]) async throws -> CompletenessFixture {
        let suite = "app.hashfleet.completeness.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let devices = payloads.indices.map { MinerDevice(name: "Miner \($0)", address: "miner\($0).invalid") }
        defaults.set(try JSONEncoder().encode(devices), forKey: "app.hashfleet.devices.v1")
        var responses: [String: CompletenessURLProtocol.Response] = [:]
        for (index, payload) in payloads.enumerated() {
            responses["miner\(index).invalid"] =
                try payload.map {
                    .init(status: 200, body: try JSONEncoder().encode(JSONValue.object($0)))
                } ?? .init(status: 503, body: Data("{}".utf8))
        }
        CompletenessURLProtocol.registry.set(responses, key: suite)
        defer { CompletenessURLProtocol.registry.set(nil, key: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CompletenessURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Completeness-Fixture": suite]
        let store = FleetStore(defaults: defaults, session: URLSession(configuration: configuration))
        await store.refresh()
        return CompletenessFixture(store: store, defaults: defaults, suite: suite)
    }

    /// The smallest payload AxeOS could return that is still a recognized device: a hostname and
    /// nothing else. It must not be treated as a miner hashing at zero.
    var hostnameOnly: [String: JSONValue] { ["hostname": .string("bitaxe")] }
    func complete(hashrate: Double, power: Double) -> [String: JSONValue] {
        ["hostname": .string("bitaxe"), "hashRate": .number(hashrate), "power": .number(power)]
    }

    // MARK: - No online miners

    @Test func unrecognizedHTTP200PayloadsAreOfflineWithoutFabricatedHistory() async throws {
        let completenessEnv = try await store([[:], ["error": .string("not a miner")]])
        let store = completenessEnv.store
        let defaults = completenessEnv.defaults
        let suite = completenessEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(store.onlineCount == 0)
        #expect(!store.hashrateReading.hasReading)
        #expect(!store.powerReading.hasReading)
        #expect(store.hashrateReading.online == 0)
        #expect(store.efficiencyReading.value == nil)
        // Sums stay at zero, but zero coverage is what distinguishes this from a real zero total.
        #expect(store.totalHashrate == 0)
        #expect(store.totalPower == 0)
        #expect(store.snapshots.values.allSatisfy { $0.history.isEmpty })
        #expect(store.snapshots.values.allSatisfy { $0.info == nil && $0.error != nil })
        // An all-offline fleet publishes a freshly checked zero-online status, not success telemetry.
        let glance = store.glance
        #expect(glance.onlineCount == 0)
        #expect(glance.minerCount == 2)
        #expect(glance.hashrateGHs == 0)
        #expect(!glance.isStale(at: Date()))
    }

    @Test func devicePresentButNeverPolledHasNoReadings() async throws {
        let suite = "app.hashfleet.completeness.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            try JSONEncoder().encode([MinerDevice(name: "Unpolled", address: "unpolled.invalid")]),
            forKey: "app.hashfleet.devices.v1"
        )
        let store = FleetStore(defaults: defaults, session: URLSession(configuration: .ephemeral))
        #expect(store.devices.count == 1)
        #expect(store.onlineCount == 0)
        #expect(!store.hashrateReading.hasReading)
        #expect(store.glance.onlineCount == 0)
        #expect(store.glance.hashrateGHs == 0)
        #expect(store.glance.isStale(at: Date()), "Never-polled devices must not look like fresh telemetry")
    }

    // MARK: - Minimal recognized info online

    @Test func hostnameOnlyOnlineReportsNoMetricsRatherThanZeroTotals() async throws {
        let completenessEnv = try await store([hostnameOnly])
        let store = completenessEnv.store
        let defaults = completenessEnv.defaults
        let suite = completenessEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(store.onlineCount == 1)
        let hashrate = store.hashrateReading
        #expect(hashrate.online == 1)
        #expect(hashrate.reporting == 0)
        #expect(!hashrate.hasReading)
        #expect(!hashrate.isPartial, "Nothing reported is a missing reading, not a subtotal")
        #expect(hashrate.missing == 1)
        #expect(!store.powerReading.hasReading)
        #expect(store.efficiencyReading.value == nil)
        #expect(store.snapshots.values.allSatisfy { $0.history.isEmpty })
        // One miner online with no usable metric must never publish a 0 GH/s fleet to a widget.
        #expect(store.glance == .empty)
    }

    @Test func captionsSayNotReportedInsteadOfShowingZero() async throws {
        let completenessEnv = try await store([hostnameOnly])
        let store = completenessEnv.store
        let defaults = completenessEnv.defaults
        let suite = completenessEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(FleetReadingCaption.hashrate(store.hashrateReading)?.contains("not a zero-hashrate fleet") == true)
        let power = FleetReadingCaption.power(store.powerReading)
        #expect(power.contains("Not reported"))
        #expect(!power.contains("Subtotal"))
        #expect(FleetReadingCaption.efficiency(store.efficiencyReading).contains("Needs every online miner"))
    }

    // MARK: - Mixed complete and partial

    @Test func mixedFleetSumsOnlyReportedValuesAndLabelsTheSubtotal() async throws {
        let completenessEnv = try await store([
            complete(hashrate: 1_200, power: 19),
            hostnameOnly,
            ["hostname": .string("third"), "hashRate": .number(800)]
        ])
        let store = completenessEnv.store
        let defaults = completenessEnv.defaults
        let suite = completenessEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(store.onlineCount == 3)
        let hashrate = store.hashrateReading
        #expect(hashrate.value == 2_000, "Only the two reported rates are summed")
        #expect(hashrate.reporting == 2)
        #expect(hashrate.online == 3)
        #expect(hashrate.isPartial)
        #expect(!hashrate.isComplete)
        let power = store.powerReading
        #expect(power.value == 19)
        #expect(power.reporting == 1)
        #expect(power.isPartial)
        let caption = try #require(FleetReadingCaption.hashrate(hashrate))
        #expect(caption.contains("2 of 3"))
        #expect(FleetReadingCaption.power(power).contains("1 of 3"))
        // Any incomplete metric must fail closed rather than publish a subtotal as a fleet total.
        #expect(store.glance == .empty)
    }

    @Test func efficiencyIsNotReportedUnlessEveryOnlineMinerReportsBothMetrics() async throws {
        let completenessEnv = try await store([
            complete(hashrate: 1_000, power: 20),
            ["hostname": .string("rate only"), "hashRate": .number(5_000)],
            ["hostname": .string("power only"), "power": .number(500)]
        ])
        let store = completenessEnv.store
        let defaults = completenessEnv.defaults
        let suite = completenessEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        let efficiency = store.efficiencyReading
        // Dividing the paired miner's 20 W by its 1 TH/s would be a per-miner figure presented as a
        // fleet one, and no caption can make that number correct. Report nothing instead.
        #expect(efficiency.value == nil)
        #expect(efficiency.reporting == 1)
        #expect(efficiency.online == 3)
        #expect(efficiency.isPartial)
        #expect(!efficiency.isComplete)
        let caption = FleetReadingCaption.efficiency(efficiency)
        #expect(caption.contains("Not reported"))
        #expect(caption.contains("1 of 3"))
    }

    @Test func pairedButZeroHashrateHasNoDefinedEfficiency() async throws {
        let completenessEnv = try await store([complete(hashrate: 0, power: 18)])
        let store = completenessEnv.store
        let defaults = completenessEnv.defaults
        let suite = completenessEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        // A genuinely reported zero is a real reading and belongs in the total.
        #expect(store.hashrateReading.hasReading)
        #expect(store.hashrateReading.isComplete)
        #expect(store.totalHashrate == 0)
        #expect(store.powerReading.value == 18)
        // Dividing by a zero hashrate is undefined, not "0 J/TH" and not infinity.
        #expect(store.efficiencyReading.value == nil)
        #expect(store.glance != .empty, "Complete readings publish even when a reported value is zero")
    }

    @Test func fullyCompleteFleetPublishesAndReportsCompleteCoverage() async throws {
        let completenessEnv = try await store([
            complete(hashrate: 1_200, power: 19),
            complete(hashrate: 800, power: 12)
        ])
        let store = completenessEnv.store
        let defaults = completenessEnv.defaults
        let suite = completenessEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(store.hashrateReading.isComplete)
        #expect(store.powerReading.isComplete)
        #expect(store.totalHashrate == 2_000)
        #expect(store.totalPower == 31)
        #expect(store.efficiencyReading.isComplete)
        #expect(store.efficiencyReading.value == 15.5)
        #expect(FleetReadingCaption.hashrate(store.hashrateReading) == nil, "A complete reading needs no qualifier")
        #expect(FleetReadingCaption.power(store.powerReading).contains("all 2"))
        #expect(store.glance.hashrateGHs == 2_000)
        #expect(store.glance.powerWatts == 31)
    }

    // MARK: - Offline behaviour preserved

    @Test func offlineMinersAreExcludedFromCoverageAndDoNotBlockPublishing() async throws {
        let completenessEnv = try await store([complete(hashrate: 1_200, power: 19), nil])
        let store = completenessEnv.store
        let defaults = completenessEnv.defaults
        let suite = completenessEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(store.onlineCount == 1)
        #expect(store.hashrateReading.online == 1, "An unreachable miner is not counted as failing to report")
        #expect(store.hashrateReading.isComplete)
        #expect(store.totalHashrate == 1_200)
        #expect(store.totalPower == 19)
        // Existing behaviour: online totals ignore offline devices, and the glance still publishes.
        #expect(store.glance.hashrateGHs == 1_200)
        #expect(store.glance.onlineCount == 1)
        #expect(store.glance.minerCount == 2)
    }

    @Test func minerWithStaleInfoAndNewErrorIsTreatedAsOffline() async throws {
        let completenessEnv = try await store([complete(hashrate: 900, power: 15)])
        let store = completenessEnv.store
        let defaults = completenessEnv.defaults
        let suite = completenessEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        let previous = store.snapshots[store.devices[0].id]?.info
        // The scoped HTTP fixture was removed after the successful initial poll. The protocol
        // still intercepts this request, but fails it locally instead of ever contacting a network.
        await store.refresh()
        #expect(store.snapshots[store.devices[0].id]?.info == previous)
        #expect(store.snapshots[store.devices[0].id]?.history.count == 1)
        #expect(store.onlineCount == 0)
        #expect(!store.hashrateReading.hasReading, "Last known values must not be summed as current")
        #expect(store.glance.onlineCount == 0)
        #expect(store.glance.hashrateGHs == 0)
    }

}

/// All requests stay in this protocol, including a request after its fixture has been removed.
private class CompletenessURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response: Sendable { let status: Int; let body: Data }
    static let registry = Registry()

    final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var fixtures: [String: [String: Response]] = [:]
        func set(_ responses: [String: Response]?, key: String) {
            lock.withLock { fixtures[key] = responses }
        }
        func response(for request: URLRequest) -> Response? {
            guard let key = request.value(forHTTPHeaderField: "X-Completeness-Fixture"),
                let host = request.url?.host
            else { return nil }
            return lock.withLock { fixtures[key]?[host] }
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.httpMethod == "GET", request.url?.path == "/api/system/info",
            let fixture = Self.registry.response(for: request), let url = request.url,
            let response = HTTPURLResponse(
                url: url,
                statusCode: fixture.status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: fixture.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
