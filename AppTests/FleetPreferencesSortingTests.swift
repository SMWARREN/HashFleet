import Foundation
import SwiftUI
import UIKit
import Testing
import HashFleetCore
@testable import HashFleet

extension FleetPreferencesTests {
    // MARK: - Sorting Missing / Offline Last

    @Test func missingOrOfflineMetricsAreAlwaysSortedLastRegardlessOfDirection() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

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

        // Test temperature: missing/offline still last
        prefs.sort = .temperature
        expectMissingLast(prefs, devices: devices, snapshots: snapshots)

        // Test acceptedShares: missing/offline still last
        prefs.sort = .acceptedShares
        expectMissingLast(prefs, devices: devices, snapshots: snapshots)

        // Test uptime: missing/offline still last
        prefs.sort = .uptime
        expectMissingLast(prefs, devices: devices, snapshots: snapshots)

        // Test firmware: missing/offline still last
        prefs.sort = .firmware
        expectMissingLast(prefs, devices: devices, snapshots: snapshots)
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

    // MARK: - Stable Ties and Natural Ordering

    @Test func stableTiesPreserveOriginalOrder() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        let minerA = MinerDevice(name: "Same", address: "http://10.0.0.1")
        let minerB = MinerDevice(name: "Same", address: "http://10.0.0.2")
        let minerC = MinerDevice(name: "Same", address: "http://10.0.0.3")

        let devices = [minerA, minerB, minerC]
        let snapshots: [UUID: MinerSnapshot] = [
            minerA.id: makeOnlineSnapshot(hashrate: 1000),
            minerB.id: makeOnlineSnapshot(hashrate: 1000),
            minerC.id: makeOnlineSnapshot(hashrate: 1000)
        ]

        let prefs = FleetPreferences(defaults: defaults)
        prefs.sort = .hashrate
        prefs.ascending = true
        let sorted = prefs.sorted(devices, snapshots: snapshots)
        #expect(sorted.map(\.id) == [minerA.id, minerB.id, minerC.id])

        prefs.ascending = false
        let sortedDesc = prefs.sorted(devices, snapshots: snapshots)
        #expect(sortedDesc.map(\.id) == [minerA.id, minerB.id, minerC.id])
    }

    @Test func addressSortUsesNaturalOrdering() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        let dev2 = MinerDevice(name: "A", address: "http://192.168.1.2")
        let dev10 = MinerDevice(name: "B", address: "http://192.168.1.10")
        let dev3 = MinerDevice(name: "C", address: "http://192.168.1.3")

        let devices = [dev10, dev2, dev3]
        let prefs = FleetPreferences(defaults: defaults)
        prefs.sort = .address
        prefs.ascending = true

        let sortedAsc = prefs.sorted(devices, snapshots: [:])
        #expect(sortedAsc.map(\.address) == ["http://192.168.1.2", "http://192.168.1.3", "http://192.168.1.10"])

        prefs.ascending = false
        let sortedDesc = prefs.sorted(devices, snapshots: [:])
        #expect(sortedDesc.map(\.address) == ["http://192.168.1.10", "http://192.168.1.3", "http://192.168.1.2"])
    }

    @Test func nameSortUsesDisplayName() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        let devZ = MinerDevice(name: "Zeta", address: "http://192.168.1.1")
        let devA = MinerDevice(name: "Alpha", address: "http://192.168.1.2")
        let devM = MinerDevice(name: "Miner 10", address: "http://192.168.1.3")
        let devM2 = MinerDevice(name: "Miner 2", address: "http://192.168.1.4")

        let devices = [devZ, devA, devM, devM2]
        let prefs = FleetPreferences(defaults: defaults)
        prefs.sort = .name
        prefs.ascending = true

        let sortedAsc = prefs.sorted(devices, snapshots: [:])
        #expect(sortedAsc.map(\.name) == ["Alpha", "Miner 2", "Miner 10", "Zeta"])

        prefs.ascending = false
        let sortedDesc = prefs.sorted(devices, snapshots: [:])
        #expect(sortedDesc.map(\.name) == ["Zeta", "Miner 10", "Miner 2", "Alpha"])
    }

    // MARK: - Input Inventory Unchanged

    @Test func absentInvalidAndStaleReadingsSortAfterGenuineZero() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = FleetPreferences(defaults: defaults)
        for (sort, key) in [
            (FleetPreferences.SortOption.hashrate, "hashRate"), (.power, "power"), (.temperature, "temp"),
            (.acceptedShares, "sharesAccepted"), (.uptime, "uptimeSeconds")
        ] {
            prefs.sort = sort
            let devices = (0..<6).map { MinerDevice(name: "M\($0)", address: "miner\($0).test") }
            let values: [JSONValue?] = [nil, .number(.nan), .number(-1), .integer(2), .integer(0), .integer(100)]
            var snapshots: [UUID: MinerSnapshot] = [:]
            for (index, device) in devices.enumerated() {
                let raw = values[index].map { [key: $0] } ?? [:]
                snapshots[device.id] = MinerSnapshot(
                    info: MinerInfo(raw: raw),
                    error: index == 5 ? "Offline" : nil,
                    updatedAt: Date()
                )
            }
            prefs.ascending = true
            #expect(
                prefs.sorted(devices, snapshots: snapshots).map(\.id) == [4, 3, 0, 1, 2, 5].map { devices[$0].id }
            )
            prefs.ascending = false
            #expect(
                prefs.sorted(devices, snapshots: snapshots).map(\.id) == [3, 4, 0, 1, 2, 5].map { devices[$0].id }
            )
        }
    }

    @Test func counterSortingPreservesLargeIntegersAndRejectsFractions() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = FleetPreferences(defaults: defaults)
        prefs.sort = .acceptedShares
        let devices = (0..<3).map { MinerDevice(name: "M\($0)", address: "miner\($0).test") }
        let values: [JSONValue] = [.integer(9_007_199_254_740_993), .number(0.5), .integer(9_007_199_254_740_992)]
        let snapshots = Dictionary(
            uniqueKeysWithValues: devices.enumerated().map { index, device in
                (device.id, MinerSnapshot(info: MinerInfo(raw: ["sharesAccepted": values[index]]), updatedAt: Date()))
            }
        )
        #expect(prefs.sorted(devices, snapshots: snapshots).map(\.id) == [2, 0, 1].map { devices[$0].id })
    }

    @Test func inputInventoryRemainsUnchanged() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        let prefs = FleetPreferences(defaults: defaults)

        // Empty inventory
        #expect(prefs.sorted([], snapshots: [:]).isEmpty)

        // Single item inventory
        let single = [MinerDevice(name: "Solo", address: "http://192.168.1.10")]
        #expect(prefs.sorted(single, snapshots: [:]).map(\.id) == single.map(\.id))

        // Multiple items inventory preservation
        let dev1 = MinerDevice(name: "M1", address: "http://192.168.1.1")
        let dev2 = MinerDevice(name: "M2", address: "http://192.168.1.2")
        let dev3 = MinerDevice(name: "M3", address: "http://192.168.1.3")
        let devices = [dev1, dev2, dev3]

        for option in FleetPreferences.SortOption.allCases {
            prefs.sort = option
            for asc in [true, false] {
                prefs.ascending = asc
                let sorted = prefs.sorted(devices, snapshots: [:])
                #expect(sorted.count == devices.count)
                #expect(Set(sorted.map(\.id)) == Set(devices.map(\.id)))
            }
        }
    }
}
