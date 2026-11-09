import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

@MainActor
struct FleetReportCaptureTests {
    @Test func captureCopiesOnlyMeasuredFieldsAndNeverLeaksPrivatePayloads() throws {
        let suite = "FleetReportCaptureTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FleetStore(defaults: defaults)
        let device = MinerDevice(name: "=secret-wallet-name", address: "192.168.222.111")
        let info = MinerInfo(raw: [
            "hostname": .string("secret-host.local"), "hashRate": .number(1_200),
            "power": .number(0), "temp": .number(0), "fanrpm": .number(0),
            "uptimeSeconds": .number(90), "stratumUser": .string("secret-wallet"),
            "stratumPassword": .string("secret-credential")
        ])
        store.devices = [device]
        store.snapshots = [device.id: MinerSnapshot(info: info, updatedAt: FleetReportFixtures.date)]
        let devicesBefore = store.devices
        let report = FleetReportSnapshot.capture(store: store, at: FleetReportFixtures.date)
        let miner = try #require(report.miners.first)
        #expect(miner.label == "Miner 1")
        #expect(miner.hashrateGHs == 1_200)
        #expect(miner.powerWatts == 0)
        #expect(miner.temperatureCelsius == nil)
        #expect(miner.fanRPM == 0)
        #expect(miner.uptimeSeconds == 90)
        #expect(miner.isCurrent)
        #expect(store.devices == devicesBefore)
        #expect(store.snapshots[device.id]?.info == info)
        #expect(store.snapshots[device.id]?.updatedAt == FleetReportFixtures.date)
        #expect(!store.isRefreshing)
        let csv = String(bytes: FleetReportCSV.encode(report), encoding: .utf8) ?? ""
        for secret in [device.name, device.address, "secret-host.local", "secret-wallet", "secret-credential", device.id.uuidString] {
            #expect(!csv.contains(secret))
            #expect(!String(describing: report).contains(secret))
        }
        // Later store changes cannot alter the reviewed snapshot or its exports.
        store.devices = []
        store.snapshots = [:]
        #expect(report.miners.count == 1)
        #expect(report.hashrate.value == 1_200)
        #expect(FleetReportSnapshot.capture(store: store, at: FleetReportFixtures.date).miners.isEmpty)
    }

    @Test func neverPolledOfflineCachedAndMalformedReadingsAreExplicit() throws {
        let suite = "FleetReportCaptureTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FleetStore(defaults: defaults)
        store.isDemo = true
        let devices = (0..<4).map { MinerDevice(name: "Private \($0)", address: "private\($0).invalid") }
        store.devices = devices
        let complete = MinerInfo(raw: ["hashRate": .number(900), "power": .number(20)])
        store.snapshots = [
            devices[1].id: MinerSnapshot(info: complete, error: "secret endpoint failed", updatedAt: FleetReportFixtures.date),
            devices[2].id: MinerSnapshot(info: complete, updatedAt: FleetReportFixtures.date, isCached: true),
            devices[3].id: MinerSnapshot(info: MinerInfo(raw: [
                "hashRate": .bool(true), "power": .number(-1), "temp": .number(-1),
                "fanrpm": .string("invalid"), "uptimeSeconds": .null
            ]), updatedAt: FleetReportFixtures.date)
        ]
        let report = FleetReportSnapshot.capture(store: store, at: FleetReportFixtures.date)
        #expect(report.isDemo)
        #expect(report.miners[0].connection == .unknown)
        #expect(report.miners[0].freshness == .unknown)
        #expect(report.miners[1].connection == .offline)
        #expect(report.miners[1].hashrateGHs == 900, "Retain labeled last-known values, but exclude them from totals")
        #expect(report.miners[2].connection == .unknown)
        #expect(report.miners[2].freshness == .cached)
        #expect(report.miners[3].connection == .online)
        #expect(report.miners[3].hashrateGHs == nil)
        #expect(report.miners[3].powerWatts == nil)
        #expect(report.miners[3].temperatureCelsius == nil)
        #expect(report.miners[3].fanRPM == nil)
        #expect(report.miners[3].uptimeSeconds == nil)
        #expect(report.hashrate.value == nil)
        #expect(report.power.value == nil)
        #expect(report.currentCount == 1)
    }

    @Test func hashrateOnlyUpdateCannotRenewOldPowerInPreviewExportsOrSubtotals() throws {
        let suite = "FleetReportCaptureTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FleetStore(defaults: defaults)
        store.isDemo = true
        let device = MinerDevice(name: "Private", address: "private.invalid")
        store.devices = [device]
        let info = MinerInfo(raw: ["hashRate": .number(1_234), "power": .number(37)])
        let now = FleetReportFixtures.date
        store.recordSuccessfulInfo(info, for: device.id, at: now.addingTimeInterval(-121))
        // The same merged object has current hashrate, but this frame never re-observed its watts.
        store.recordSuccessfulInfo(info, for: device.id, at: now, hasFreshTemperature: false, hasFreshPower: false)
        let report = FleetReportSnapshot.capture(store: store, at: now)
        let miner = try #require(report.miners.first)
        #expect(miner.isCurrent)
        #expect(miner.hashrateGHs == 1_234)
        #expect(miner.powerWatts == nil)
        #expect(report.power.value == nil)
        #expect(report.power.reporting == 0)
        #expect(report.power.eligible == 1)
        let csv = String(bytes: FleetReportCSV.encode(report), encoding: .utf8) ?? ""
        #expect(!csv.contains("\"37.0\""))
        #expect(csv.contains("Power uses its own observation time"))
        // A subsequent actual power observation restores exactly the measured value.
        store.recordSuccessfulInfo(info, for: device.id, at: now, hasFreshPower: true)
        #expect(FleetReportSnapshot.capture(store: store, at: now).power.value == 37)
    }

    @Test func powerTimestampOverridesSnapshotClockWithLegacyFallbackOnlyWhenAbsent() throws {
        let suite = "FleetReportCaptureTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FleetStore(defaults: defaults)
        let devices = (0..<4).map { MinerDevice(name: "Private \($0)", address: "private\($0).invalid") }
        store.devices = devices
        let now = FleetReportFixtures.date
        let info = MinerInfo(raw: ["hashRate": .number(1_000), "power": .number(20)])
        store.snapshots = [
            devices[0].id: MinerSnapshot(info: info, updatedAt: now, powerObservedAt: now.addingTimeInterval(1)),
            devices[1].id: MinerSnapshot(info: info, updatedAt: now, powerObservedAt: now.addingTimeInterval(-120)),
            devices[2].id: MinerSnapshot(info: info, updatedAt: now),
            devices[3].id: MinerSnapshot(info: info)
        ]
        let report = FleetReportSnapshot.capture(store: store, at: now)
        #expect(report.miners[0].powerWatts == nil)
        #expect(report.miners[1].powerWatts == 20)
        #expect(report.miners[2].powerWatts == 20)
        #expect(report.miners[3].powerWatts == nil)
        #expect(report.power.value == 40)
        #expect(report.power.reporting == 2)
        #expect(report.power.eligible == 3)
    }

    @Test func unchangedCompletePollRefreshesReportWithoutInventingNewValues() throws {
        let suite = "FleetReportCaptureTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FleetStore(defaults: defaults)
        store.isDemo = true
        let device = MinerDevice(name: "Private", address: "private.invalid")
        store.devices = [device]
        let info = MinerInfo(raw: ["hashRate": .number(1_234), "power": .number(37)])
        let now = FleetReportFixtures.date
        let old = now.addingTimeInterval(-121)
        store.recordSuccessfulInfo(info, for: device.id, at: old)
        store.recordSuccessfulInfo(info, for: device.id, at: now)
        #expect(store.snapshots[device.id]?.updatedAt == old)
        #expect(store.snapshots[device.id]?.completeSnapshotAt == now)
        let report = FleetReportSnapshot.capture(store: store, at: now)
        let miner = try #require(report.miners.first)
        #expect(miner.isCurrent)
        #expect(miner.observedAt == now)
        #expect(report.hashrate.value == 1_234)
        #expect(report.power.value == 37)
    }
}
