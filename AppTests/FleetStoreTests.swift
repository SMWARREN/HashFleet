import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

@Suite(.serialized) @MainActor
struct FleetStoreTests {
    @Test func automaticModelNameAndExplicitLocalNameSurviveRefreshAndRelaunch() async throws {
        let fleetEnv = try fixture()
        let store = fleetEnv.store
        let defaults = fleetEnv.defaults
        let suite = fleetEnv.suite
        defer { store.cancelRefresh(); defaults.removePersistentDomain(forName: suite) }
        try store.add(name: "", address: "gamma.test")
        let device = try #require(store.devices.first)
        #expect(device.usesAutomaticName == true)
        await store.refresh()
        #expect(store.devices.first?.name == "Gamma")
        try store.rename(device, name: "  Desk miner  ")
        #expect(store.devices.first?.name == "Desk miner")
        #expect(store.devices.first?.usesAutomaticName == false)
        await store.refresh()
        #expect(store.devices.first?.name == "Desk miner")
        let restored = FleetStore(defaults: defaults)
        #expect(restored.devices.first?.name == "Desk miner")
        #expect(restored.snapshots[device.id]?.isCached == true)
        let observed = restored.snapshots[device.id]?.updatedAt
        try restored.rename(device, name: "Offline desk")
        #expect(restored.devices.first?.name == "Offline desk")
        #expect(restored.snapshots[device.id]?.updatedAt == observed)
        #expect(restored.onlineCount == 0)
        try restored.rename(device, name: "")
        #expect(restored.devices.first?.name == "Gamma")
        #expect(restored.devices.first?.usesAutomaticName == true)
        restored.remove(device)
        #expect(FleetStore(defaults: defaults).devices.isEmpty)
    }

    @Test func sameMinerAddedByIPAndHostnameCollapsesToOneAfterRefresh() async throws {
        let fleetEnv = try fixture()
        let store = fleetEnv.store
        let defaults = fleetEnv.defaults
        let suite = fleetEnv.suite
        defer { store.cancelRefresh(); defaults.removePersistentDomain(forName: suite) }

        // The same physical miner added two ways (its IP and its mDNS-style hostname). The
        // add-time guard only blocks byte-identical URLs, so both are accepted here.
        try store.add(name: "By IP", address: "gamma.test")
        try store.add(name: "By hostname", address: "gamma-alias.test")
        #expect(store.devices.count == 2)

        // Once snapshots arrive, both report the same MAC (in different formats) and collapse.
        await store.refresh()
        #expect(store.devices.count == 1)
        // The first-added device is the survivor, keeping its name and history.
        #expect(store.devices.first?.name == "By IP")
        // The duplicate is gone from persistence too.
        #expect(FleetStore(defaults: defaults).devices.count == 1)
    }

    @Test func explicitGenericNameIsPreservedAndLegacyDefaultUpgrades() async throws {
        let legacy = MinerDevice(name: "Bitaxe", address: "gamma.test")
        let fleetEnv = try fixture(devices: [legacy])
        let store = fleetEnv.store
        let defaults = fleetEnv.defaults
        let suite = fleetEnv.suite
        defer { store.cancelRefresh(); defaults.removePersistentDomain(forName: suite) }
        await store.refresh()
        #expect(store.devices.first?.name == "Gamma")
        try store.rename(legacy, name: "Bitaxe")
        await store.refresh()
        #expect(store.devices.first?.name == "Bitaxe")
        #expect(store.devices.first?.usesAutomaticName == false)
        #expect(FleetStore(defaults: defaults).devices.first?.name == "Bitaxe")
    }

    @Test func localNamesAreBoundedAndDemoRenameCannotAlterSavedFleet() throws {
        let fleetEnv = try fixture()
        let store = fleetEnv.store
        let defaults = fleetEnv.defaults
        let suite = fleetEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(throws: (any Error).self) {
            try store.add(name: String(repeating: "x", count: 65), address: "gamma.test")
        }
        try store.add(name: "Desk", address: "gamma.test")
        let real = try #require(store.devices.first)
        #expect(throws: (any Error).self) { try store.rename(real, name: "bad\nname") }
        #expect(store.devices.first?.name == "Desk")
        #expect(FleetFixtureProtocol.counter.value(for: suite) == 0)
        let saved = defaults.data(forKey: "app.hashfleet.devices.v1")
        store.loadDemo()
        #expect(throws: (any Error).self) { try store.rename(store.devices[0], name: "Changed demo") }
        #expect(defaults.data(forKey: "app.hashfleet.devices.v1") == saved)
        store.clearDemo()
        #expect(store.devices.first?.name == "Desk")
    }

    @Test func oldDeviceJSONDecodesWithoutNamingMode() throws {
        let id = UUID()
        let data = Data("{\"id\":\"\(id.uuidString)\",\"name\":\"Old custom\",\"address\":\"gamma.test\"}".utf8)
        let device = try JSONDecoder().decode(MinerDevice.self, from: data)
        #expect(device.name == "Old custom" && device.usesAutomaticName == nil)
    }

    @Test func cachedSnapshotRelaunchIsOfflineAndRetainsObservedTime() async throws {
        let real = MinerDevice(name: "Cached", address: "online.test")
        let fleetEnv = try fixture(devices: [real])
        let store = fleetEnv.store
        let defaults = fleetEnv.defaults
        let suite = fleetEnv.suite
        defer { store.cancelRefresh(); defaults.removePersistentDomain(forName: suite) }
        await store.refresh()
        let live = try #require(store.snapshots[real.id])
        #expect(live.error == nil)
        #expect(defaults.data(forKey: FleetStore.snapshotCacheKey) != nil)
        let restored = FleetStore(defaults: defaults)
        let cached = try #require(restored.snapshots[real.id])
        #expect(cached.info?.raw["hashRate"] == live.info?.raw["hashRate"])
        #expect(cached.updatedAt == live.updatedAt)
        #expect(cached.error != nil && restored.onlineCount == 0)
        #expect(cached.isReconnecting)
        #expect(FleetStatusTickerModel(devices: restored.devices, snapshots: restored.snapshots).items.first?.status == .reconnecting)
        #expect(!MinerWriteAvailability.allows(cached))
        #expect(restored.lastRefresh == nil)
    }

    @Test func snapshotCacheNeverPersistsCredentialsOrUnknownFirmwareFields() throws {
        let info = MinerInfo(raw: [
            "hostname": .string("Gamma"), "frequency": .integer(600), "coreVoltage": .integer(1150),
            "errorPercentage": .number(0.12),
            "wifiPass": .string("wifi-secret"), "stratumUser": .string("private-wallet"),
            "customFirmwareToken": .string("future-secret"),
            "stratumURL": .string("stratum+tcp://user:password@solo.ckpool.org:3333/private?token=hidden"),
            "pools": .array([
                .object([
                    "id": .integer(0), "stratumURL": .string("us1.solopool.org"),
                    "stratumPort": .integer(8004), "stratumUser": .string("another-wallet"),
                    "stratumPassword": .string("pool-secret")
                ])
            ])
        ])
        let entry = MinerSnapshotCacheEntry(info: info, observedAt: Date())
        let json = String(bytes: try JSONEncoder().encode(entry), encoding: .utf8) ?? ""
        for secret in [
            "wifi-secret", "private-wallet", "future-secret", "password", "hidden", "another-wallet", "pool-secret",
            "/private"
        ] {
            #expect(!json.contains(secret))
        }
        #expect(entry.fields["frequency"]?.intValue == 600)
        #expect(entry.restored.info?.raw["errorPercentage"]?.doubleValue == 0.12)
        #expect(entry.fields["stratumURL"]?.stringValue == "solo.ckpool.org:3333")
        #expect(entry.restored.error != nil)
    }

    @Test func cacheSurvivesDemoUnchangedAndDeviceRemovalDeletesIt() async throws {
        let real = MinerDevice(name: "Cached", address: "online.test")
        let fleetEnv = try fixture(devices: [real])
        let store = fleetEnv.store
        let defaults = fleetEnv.defaults
        let suite = fleetEnv.suite
        defer { store.cancelRefresh(); defaults.removePersistentDomain(forName: suite) }
        await store.refresh()
        let cached = try #require(defaults.data(forKey: FleetStore.snapshotCacheKey))
        store.loadPoolIconDemo()
        await store.refresh()
        store.previewPool(slot: 6, for: store.devices[0].id)
        #expect(defaults.data(forKey: FleetStore.snapshotCacheKey) == cached)
        store.clearDemo()
        #expect(store.snapshots[real.id]?.info != nil)
        #expect(store.snapshots[real.id]?.error != nil)
        #expect(store.onlineCount == 0)
        store.remove(real)
        let restored = FleetStore(defaults: defaults)
        #expect(restored.devices.isEmpty && restored.snapshots.isEmpty)
        let entries = try JSONDecoder().decode(
            [String: MinerSnapshotCacheEntry].self,
            from: #require(defaults.data(forKey: FleetStore.snapshotCacheKey))
        )
        #expect(entries[real.id.uuidString] == nil)
    }

    @Test func corruptCacheNeverDestroysSavedDevices() throws {
        let real = MinerDevice(name: "Cached", address: "offline.test")
        let fleetEnv = try fixture(devices: [real])
        let defaults = fleetEnv.defaults
        let suite = fleetEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        let bytes = Data("broken-cache".utf8)
        defaults.set(bytes, forKey: FleetStore.snapshotCacheKey)
        let restored = FleetStore(defaults: defaults)
        #expect(restored.devices == [real])
        #expect(restored.snapshots.isEmpty)
        #expect(defaults.data(forKey: FleetStore.snapshotCacheKey) == bytes)
    }
    struct FleetStoreFixture {
        let store: FleetStore
        let defaults: UserDefaults
        let suite: String
    }

    func fixture(devices: [MinerDevice] = []) throws -> FleetStoreFixture {
        let suite = "app.hashfleet.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(try JSONEncoder().encode(devices), forKey: "app.hashfleet.devices.v1")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FleetFixtureProtocol.self]
        configuration.httpAdditionalHeaders = ["X-HashFleet-Test-ID": suite]
        return FleetStoreFixture(
            store: FleetStore(defaults: defaults, session: URLSession(configuration: configuration)),
            defaults: defaults,
            suite: suite
        )
    }

    @Test func poolIconDemoCoversEveryPoolOnEveryMinerWithoutPollingOrChangingSavedFleet() async throws {
        let real = MinerDevice(name: "Real miner", address: "online.test")
        let fleetEnv = try fixture(devices: [real])
        let store = fleetEnv.store
        let defaults = fleetEnv.defaults
        let suite = fleetEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        let persisted = defaults.data(forKey: "app.hashfleet.devices.v1")
        store.loadDemo()
        store.loadPoolIconDemo()
        #expect(store.isDemo && store.isPoolIconDemo)
        #expect(store.devices.count == SoloPoolPreset.allCases.count)
        let demoDevices = store.devices
        store.loadPoolIconDemo()
        #expect(store.devices == demoDevices)
        let count = FleetFixtureProtocol.counter.value(for: suite)
        for (index, device) in demoDevices.enumerated() {
            let original = try #require(store.snapshots[device.id]?.info)
            #expect(ConfiguredMiningPool.resolve(info: original).count == SoloPoolPreset.allCases.count)
            #expect(ConfiguredMiningPool.resolve(info: original).allSatisfy { $0.address == nil })
            #expect(MinerMiningContext.resolve(info: original).pool?.host == SoloPoolPreset.allCases[index].server)
            for (slot, preset) in SoloPoolPreset.allCases.enumerated() {
                let others = store.snapshots.filter { $0.key != device.id }.mapValues { $0.info?.raw }
                store.previewPool(slot: slot, for: device.id)
                let context = MinerMiningContext.resolve(info: store.snapshots[device.id]?.info)
                #expect(context.coinLabel == preset.coin)
                #expect(context.pool?.host == preset.server)
                #expect(context.pool?.isActive == true)
                #expect(store.snapshots.filter { $0.key != device.id }.mapValues { $0.info?.raw } == others)
            }
            store.previewPool(slot: index, for: device.id)
        }
        await store.refresh()
        #expect(FleetFixtureProtocol.counter.value(for: suite) == count)
        let before = store.snapshots.mapValues { $0.info?.raw }
        store.previewPool(slot: -1, for: demoDevices[0].id)
        store.previewPool(slot: SoloPoolPreset.allCases.count, for: demoDevices[0].id)
        store.previewPool(slot: 1, for: real.id)
        #expect(store.snapshots.mapValues { $0.info?.raw } == before)
        #expect(defaults.data(forKey: "app.hashfleet.devices.v1") == persisted)
        store.clearDemo()
        #expect(!store.isDemo && !store.isPoolIconDemo)
        #expect(store.devices == [real])
        store.previewPool(slot: 1, for: real.id)
        #expect(store.snapshots.isEmpty)
        #expect(defaults.data(forKey: "app.hashfleet.devices.v1") == persisted)
    }

    @Test func foregroundReconnectChecksEachMinerBeforeShowingItsConnectionResult() async throws {
        let online = MinerDevice(name: "Online", address: "online.test")
        let offline = MinerDevice(name: "Offline", address: "offline.test")
        let fleetEnv = try fixture(devices: [online, offline])
        let store = fleetEnv.store
        defer { store.cancelRefresh(); fleetEnv.defaults.removePersistentDomain(forName: fleetEnv.suite) }
        store.preferences.realtimeMonitoring = false
        store.preferences.telemetryStorageEnabled = false
        await store.refresh()
        let reading = try #require(store.snapshots[online.id])
        let failure = try #require(store.snapshots[offline.id]?.error)

        store.beginReconnecting()
        #expect(store.reconnectingCount == 2)
        #expect(store.snapshots[online.id]?.info?.raw == reading.info?.raw)
        #expect(store.snapshots[online.id]?.updatedAt == reading.updatedAt)
        #expect(store.snapshots[offline.id]?.error == failure)
        #expect(MinerWriteAvailability.allows(store.snapshots[online.id]) == false)
        #expect(FleetStatusTickerModel(devices: store.devices, snapshots: store.snapshots).items.allSatisfy {
            $0.status == .reconnecting
        })

        // Scene cancellation must not reveal yesterday's error before the next check begins.
        store.cancelRefresh()
        #expect(store.isReconnecting)
        await store.runMonitoring()
        #expect(store.isReconnecting == false)
        #expect(store.snapshots[online.id]?.error == nil)
        #expect(store.snapshots[offline.id]?.error != nil)
        #expect(store.onlineCount == 1)
        let ticker = FleetStatusTickerModel(devices: store.devices, snapshots: store.snapshots)
        #expect(ticker.items.first { $0.id == online.id }?.status == .online)
        #expect(ticker.items.first { $0.id == offline.id }?.status == .offline)
    }

    @Test func reconnectingHoldsConnectivityBannersAndKeepsMilestoneBannersVisible() {
        let deviceID = UUID()
        for kind in [MinerStateChangeEvent.Kind.offline, .backOnline] {
            let alert = FleetInAppAlert(.stateChange(MinerStateChangeEvent(
                deviceID: deviceID, minerName: "Desk", kind: kind,
                detail: "Previous connection result", occurredAt: .now
            )))
            #expect(alert.shouldPresent(isReconnecting: true) == false)
            #expect(alert.shouldPresent(isReconnecting: false))
        }
        let record = FleetInAppAlert(.bestShare(MinerBestShareEvent(
            deviceID: deviceID, minerName: "Desk", kind: .allTime,
            displayValue: "10G", rawValue: "10G", occurredAt: .now
        )))
        #expect(record.shouldPresent(isReconnecting: true))
    }

    @Test func reconnectingDoesNotChangeDemoReadings() throws {
        let fleetEnv = try fixture()
        let store = fleetEnv.store
        defer { fleetEnv.defaults.removePersistentDomain(forName: fleetEnv.suite) }
        store.loadDemo()
        let before = store.snapshots.mapValues { $0.info?.raw }
        store.beginReconnecting()
        #expect(store.isReconnecting == false)
        #expect(store.snapshots.mapValues { $0.info?.raw } == before)
    }

    @Test func pollingExcludesOfflineFromTotalsAndPreservesErrors() async throws {
        let online = MinerDevice(name: "Online", address: "online.test")
        let offline = MinerDevice(name: "Offline", address: "offline.test")
        let fleetEnv = try fixture(devices: [online, offline])
        let store = fleetEnv.store
        let defaults = fleetEnv.defaults
        let suite = fleetEnv.suite
        defer { defaults.removePersistentDomain(forName: suite) }
        await store.refresh()
        #expect(store.onlineCount == 1)
        #expect(store.totalHashrate == 1200)
        #expect(store.totalPower == 19)
        #expect(store.snapshots[online.id]?.history.count == 1)
        #expect(store.snapshots[offline.id]?.info == nil)
        #expect(store.snapshots[offline.id]?.error != nil)
        #expect(store.lastRefresh != nil)
        #expect(!store.isRefreshing)
    }

    // MARK: - DemoFleet, CacheEntry, Empty Fleet, and Sorting Tests

    @Test func demoFleetDevicesAndHistoryModes() {
        let devices = DemoFleet.devices
        #expect(devices.count == 3)
        #expect(devices.allSatisfy { $0.address.hasSuffix(".invalid") })

        let emptySnapshots = DemoFleet.snapshots(for: devices, historyMode: .empty)
        #expect(emptySnapshots.count == 3)
        for dev in devices {
            let snap = emptySnapshots[dev.id]
            #expect(snap?.error == nil)
            #expect(snap?.info != nil)
            #expect(snap?.history.isEmpty == true)
        }

        let staleSnapshots = DemoFleet.snapshots(for: devices, historyMode: .staleDaily)
        #expect(staleSnapshots.count == 3)
        for dev in devices {
            let snap = staleSnapshots[dev.id]
            #expect(snap?.history.isEmpty == false)
        }
    }

    @Test func snapshotCacheEntryFiltersNonFiniteNumbersAndLongStrings() {
        let longString = String(repeating: "a", count: 300)
        let raw: [String: JSONValue] = [
            "hostname": .string("ValidHost"),
            "boardVersion": .string(longString),
            "hashRate": .number(Double.nan),
            "power": .number(Double.infinity),
            "frequency": .integer(600),
            "temp": .number(55.5)
        ]
        let info = MinerInfo(raw: raw)
        let entry = MinerSnapshotCacheEntry(info: info, observedAt: Date())
        #expect(entry.fields["hostname"]?.stringValue == "ValidHost")
        #expect(entry.fields["boardVersion"] == nil)
        #expect(entry.fields["hashRate"] == nil)
        #expect(entry.fields["power"] == nil)
        #expect(entry.fields["frequency"]?.intValue == 600)
        #expect(entry.fields["temp"]?.doubleValue == 55.5)

        let restored = entry.restored
        #expect(restored.isCached == true)
        #expect(restored.error?.contains("Offline") == true)
    }

    @Test func emptyFleetStoreHasZeroTotals() throws {
        let fleetEnv = try fixture(devices: [])
        let store = fleetEnv.store
        defer { fleetEnv.defaults.removePersistentDomain(forName: fleetEnv.suite) }

        #expect(store.devices.isEmpty)
        #expect(store.snapshots.isEmpty)
        #expect(store.onlineCount == 0)
        #expect(store.totalHashrate == 0)
        #expect(store.totalPower == 0)
        #expect(store.lastRefresh == nil)
    }

    @Test func fleetPreferencesSortingOrdersMinersAndPlacesMissingLast() {
        let suite = "app.hashfleet.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var prefs = FleetPreferences(defaults: defaults)

        let devA = MinerDevice(name: "Alpha", address: "10.0.0.1")
        let devB = MinerDevice(name: "Beta", address: "10.0.0.2")
        let devC = MinerDevice(name: "Gamma", address: "10.0.0.3")

        let snapA = MinerSnapshot(info: MinerInfo(raw: ["hashRate": .number(500), "power": .integer(10)]), updatedAt: Date())
        let snapB = MinerSnapshot(info: MinerInfo(raw: ["hashRate": .number(1200), "power": .integer(20)]), updatedAt: Date())
        let snapC = MinerSnapshot(error: "Offline") // missing metric

        let snapshots = [devA.id: snapA, devB.id: snapB, devC.id: snapC]

        // Sort by name ascending
        prefs.sort = .name
        prefs.ascending = true
        let byNameAsc = prefs.sorted([devC, devB, devA], snapshots: snapshots)
        #expect(byNameAsc.map(\.name) == ["Alpha", "Beta", "Gamma"])

        // Sort by name descending
        prefs.ascending = false
        let byNameDesc = prefs.sorted([devA, devB, devC], snapshots: snapshots)
        #expect(byNameDesc.map(\.name) == ["Gamma", "Beta", "Alpha"])

        // Sort by hashrate descending: Beta (1200), Alpha (500), Gamma (missing, last)
        prefs.sort = .hashrate
        prefs.ascending = false
        let byHashDesc = prefs.sorted([devA, devC, devB], snapshots: snapshots)
        #expect(byHashDesc.map(\.name) == ["Beta", "Alpha", "Gamma"])

        // Sort by hashrate ascending: Alpha (500), Beta (1200), Gamma (missing, still last!)
        prefs.ascending = true
        let byHashAsc = prefs.sorted([devC, devB, devA], snapshots: snapshots)
        #expect(byHashAsc.map(\.name) == ["Alpha", "Beta", "Gamma"])
    }

}

final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var stops: [String: Int] = [:]
    func value(for fixture: String, stopped: Bool = false) -> Int {
        lock.withLock { (stopped ? stops : counts)[fixture, default: 0] }
    }
    func increment(for fixture: String, stopped: Bool = false) {
        lock.withLock {
            if stopped { stops[fixture, default: 0] += 1 } else { counts[fixture, default: 0] += 1 }
        }
    }
}

class FleetFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let counter = RequestCounter()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let fixture = request.value(forHTTPHeaderField: "X-HashFleet-Test-ID") ?? "unknown"
        Self.counter.increment(for: fixture)
        if request.url?.host == "delayed.test" { return }
        guard ["online.test", "gamma.test", "gamma-alias.test"].contains(request.url?.host ?? ""), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // gamma.test and gamma-alias.test model the same physical miner reached two ways: they
        // report the same hardware MAC so the fleet can collapse the duplicate.
        let json: String
        switch url.host {
        case "gamma.test":
            json = #"{"hashRate":1200,"power":19,"temp":54,"hostname":"bitaxe","ASICModel":"BM1370","boardVersion":"602","macAddr":"AA:BB:CC:11:22:33"}"#
        case "gamma-alias.test":
            json = #"{"hashRate":1200,"power":19,"temp":54,"hostname":"bitaxe","ASICModel":"BM1370","boardVersion":"602","macAddr":"aa-bb-cc-11-22-33"}"#
        default:
            json = #"{"hashRate":1200,"power":19,"temp":54,"hostname":"fixture"}"#
        }
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {
        let fixture = request.value(forHTTPHeaderField: "X-HashFleet-Test-ID") ?? "unknown"
        Self.counter.increment(for: fixture, stopped: true)
    }
}
