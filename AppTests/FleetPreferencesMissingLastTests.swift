import Foundation
import Testing
import SwiftUI
@testable import HashFleet
import HashFleetCore

@MainActor
struct FleetPreferencesMissingLastTests {
    private func makeSuite() throws -> (UserDefaults, String) {
        let suite = "FleetPreferencesMissingLastTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (defaults, suite)
    }

    private func makeOnlineSnapshot(
        hashrate: Double? = nil,
        power: Double? = nil,
        temp: Double? = nil,
        sharesAccepted: Int? = nil,
        uptimeSeconds: Double? = nil,
        version: String? = nil,
        user: String? = nil,
        pool: String? = nil
    ) -> MinerSnapshot {
        var raw = [String: JSONValue]()
        if let hashrate { raw["hashrate"] = .number(hashrate) }
        if let power { raw["power"] = .number(power) }
        if let temp { raw["temp"] = .number(temp) }
        if let sharesAccepted { raw["sharesAccepted"] = .integer(Int64(sharesAccepted)) }
        if let uptimeSeconds { raw["uptimeSeconds"] = .number(uptimeSeconds) }
        if let version { raw["version"] = .string(version) }
        if let user { raw["stratumUser"] = .string(user) }
        if let pool { raw["stratumURL"] = .string(pool) }
        return MinerSnapshot(info: MinerInfo(raw: raw), error: nil, updatedAt: Date(), history: [])
    }

    private func makeOfflineSnapshot(error: String = "Connection refused") -> MinerSnapshot {
        MinerSnapshot(info: nil, error: error, updatedAt: Date(), history: [])
    }
    private func expectMissingLast(
        _ prefs: FleetPreferences,
        devices: [MinerDevice],
        snapshots: [UUID: MinerSnapshot]
    ) {
        prefs.ascending = true
        #expect(
            prefs.sorted(devices, snapshots: snapshots).map(\.name) == [
                "Slow Miner", "Fast Miner", "Unprobed Miner", "Offline Miner"
            ]
        )
        prefs.ascending = false
        #expect(
            prefs.sorted(devices, snapshots: snapshots).map(\.name) == [
                "Fast Miner", "Slow Miner", "Unprobed Miner", "Offline Miner"
            ]
        )
    }

    @Test func missingOrOfflineMetricsAreAlwaysSortedLastRegardlessOfDirection_HashRate_And_Power() throws {
        let (defaults, _) = try makeSuite()
        let fast = MinerDevice(name: "Fast Miner", address: "http://192.168.1.11")
        let slow = MinerDevice(name: "Slow Miner", address: "http://192.168.1.12")
        let offline = MinerDevice(name: "Offline Miner", address: "http://192.168.1.13")
        let noSnapshot = MinerDevice(name: "Unprobed Miner", address: "http://192.168.1.14")

        let devices = [noSnapshot, slow, offline, fast]
        let snapshots: [UUID: MinerSnapshot] = [
            fast.id: makeOnlineSnapshot(
                hashrate: 1500,
                power: 25,
                temp: 65,
                sharesAccepted: 200,
                uptimeSeconds: 7200,
                version: "v2.0"
            ),
            slow.id: makeOnlineSnapshot(
                hashrate: 500,
                power: 15,
                temp: 45,
                sharesAccepted: 50,
                uptimeSeconds: 1800,
                version: "v1.0"
            ),
            offline.id: makeOfflineSnapshot()
        ]

        let prefs = FleetPreferences(defaults: defaults)

        // Test hashrate ascending: slow (500), fast (1500), then missing/offline in stable order (noSnapshot, offline)
        prefs.sort = .hashrate
        prefs.ascending = true
        let sortedAsc = prefs.sorted(devices, snapshots: snapshots)
        #expect(sortedAsc.map(\.name) == ["Slow Miner", "Fast Miner", "Unprobed Miner", "Offline Miner"])

        // Test hashrate descending: fast (1500), slow (500), then missing/offline STILL last (noSnapshot, offline)
        prefs.ascending = false
        let sortedDesc = prefs.sorted(devices, snapshots: snapshots)
        #expect(sortedDesc.map(\.name) == ["Fast Miner", "Slow Miner", "Unprobed Miner", "Offline Miner"])

        // Test power: missing/offline still last
        prefs.sort = .power
        expectMissingLast(prefs, devices: devices, snapshots: snapshots)
    }

    @Test func missingOrOfflineMetricsAreAlwaysSortedLastRegardlessOfDirection_Temperature_And_Shares() throws {
        let (defaults, _) = try makeSuite()
        let fast = MinerDevice(name: "Fast Miner", address: "http://192.168.1.11")
        let slow = MinerDevice(name: "Slow Miner", address: "http://192.168.1.12")
        let offline = MinerDevice(name: "Offline Miner", address: "http://192.168.1.13")
        let noSnapshot = MinerDevice(name: "Unprobed Miner", address: "http://192.168.1.14")

        let devices = [noSnapshot, slow, offline, fast]
        let snapshots: [UUID: MinerSnapshot] = [
            fast.id: makeOnlineSnapshot(
                hashrate: 1500,
                power: 25,
                temp: 65,
                sharesAccepted: 200,
                uptimeSeconds: 7200,
                version: "v2.0"
            ),
            slow.id: makeOnlineSnapshot(
                hashrate: 500,
                power: 15,
                temp: 45,
                sharesAccepted: 50,
                uptimeSeconds: 1800,
                version: "v1.0"
            ),
            offline.id: makeOfflineSnapshot()
        ]

        let prefs = FleetPreferences(defaults: defaults)

        // Test temperature: missing/offline still last
        prefs.sort = .temperature
        expectMissingLast(prefs, devices: devices, snapshots: snapshots)

        // Test acceptedShares: missing/offline still last
        prefs.sort = .acceptedShares
        expectMissingLast(prefs, devices: devices, snapshots: snapshots)
    }

    @Test func missingOrOfflineMetricsAreAlwaysSortedLastRegardlessOfDirection_Uptime_And_Firmware() throws {
        let (defaults, _) = try makeSuite()
        let fast = MinerDevice(name: "Fast Miner", address: "http://192.168.1.11")
        let slow = MinerDevice(name: "Slow Miner", address: "http://192.168.1.12")
        let offline = MinerDevice(name: "Offline Miner", address: "http://192.168.1.13")
        let noSnapshot = MinerDevice(name: "Unprobed Miner", address: "http://192.168.1.14")

        let devices = [noSnapshot, slow, offline, fast]
        let snapshots: [UUID: MinerSnapshot] = [
            fast.id: makeOnlineSnapshot(
                hashrate: 1500,
                power: 25,
                temp: 65,
                sharesAccepted: 200,
                uptimeSeconds: 7200,
                version: "v2.0"
            ),
            slow.id: makeOnlineSnapshot(
                hashrate: 500,
                power: 15,
                temp: 45,
                sharesAccepted: 50,
                uptimeSeconds: 1800,
                version: "v1.0"
            ),
            offline.id: makeOfflineSnapshot()
        ]

        let prefs = FleetPreferences(defaults: defaults)

        // Test uptime: missing/offline still last
        prefs.sort = .uptime
        expectMissingLast(prefs, devices: devices, snapshots: snapshots)

        // Test firmware: missing/offline still last
        prefs.sort = .firmware
        expectMissingLast(prefs, devices: devices, snapshots: snapshots)
    }

    // MARK: - Stable Ties and Natural Ordering
}
