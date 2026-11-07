//
//  FleetHashrateShareTests.swift
//  MacAppTests
//
//  Tests for FleetHashrateShare calculations and pure logic.
//

import Foundation
import Testing
import HashFleetCore
@testable import HashFleetMac

@Suite("Fleet Hashrate Share")
struct FleetHashrateShareTests {

    private func makeDevice(
        name: String,
        kind: MinerDevice.Kind = .espMiner
    ) -> MinerDevice {
        MinerDevice(
            id: UUID(),
            name: name,
            address: "192.168.1.\(Int.random(in: 10...200))",
            kind: kind
        )
    }

    private func makeSnapshot(
        hashrate: Double?,
        error: String? = nil,
        isReconnecting: Bool = false
    ) -> MinerSnapshot {
        var raw: [String: JSONValue] = [:]
        if let hashrate {
            raw["hashRate"] = .number(hashrate)
        }
        let info = hashrate != nil ? MinerInfo(raw: raw) : nil
        return MinerSnapshot(
            info: info,
            error: error,
            updatedAt: Date(),
            isCached: false,
            isReconnecting: isReconnecting
        )
    }

    // MARK: - Sorting

    @Test func sortingDescendingByHashrate() {
        let dev1 = makeDevice(name: "Axe Slow")
        let dev2 = makeDevice(name: "Axe Fast")
        let dev3 = makeDevice(name: "Axe Medium")

        let devices = [dev1, dev2, dev3]
        let snapshots: [UUID: MinerSnapshot] = [
            dev1.id: makeSnapshot(hashrate: 200.0),
            dev2.id: makeSnapshot(hashrate: 1000.0),
            dev3.id: makeSnapshot(hashrate: 600.0)
        ]

        let slices = FleetHashrateShare.slices(devices: devices, snapshots: snapshots)

        #expect(slices.count == 3)
        #expect(slices[0].id == dev2.id)
        #expect(slices[0].name == "Axe Fast")
        #expect(slices[0].hashrate == 1000.0)
        #expect(slices[0].colorIndex == 0)

        #expect(slices[1].id == dev3.id)
        #expect(slices[1].name == "Axe Medium")
        #expect(slices[1].hashrate == 600.0)
        #expect(slices[1].colorIndex == 1)

        #expect(slices[2].id == dev1.id)
        #expect(slices[2].name == "Axe Slow")
        #expect(slices[2].hashrate == 200.0)
        #expect(slices[2].colorIndex == 2)
    }

    @Test func sortingStableTieBreakByName() {
        let devB = makeDevice(name: "Miner Beta")
        let devA = makeDevice(name: "Miner Alpha")

        let devices = [devB, devA]
        let snapshots: [UUID: MinerSnapshot] = [
            devB.id: makeSnapshot(hashrate: 500.0),
            devA.id: makeSnapshot(hashrate: 500.0)
        ]

        let slices = FleetHashrateShare.slices(devices: devices, snapshots: snapshots)

        #expect(slices.count == 2)
        #expect(slices[0].name == "Miner Alpha")
        #expect(slices[1].name == "Miner Beta")
    }

    // MARK: - Zero and Offline Exclusion

    @Test func zeroAndOfflineExclusion() {
        let onlineValid = makeDevice(name: "Online Miner")
        let zeroRate = makeDevice(name: "Zero Rate Miner")
        let negativeRate = makeDevice(name: "Negative Rate Miner")
        let withError = makeDevice(name: "Error Miner")
        let reconnecting = makeDevice(name: "Reconnecting Miner")
        let noInfo = makeDevice(name: "No Info Miner")
        let notInSnapshots = makeDevice(name: "Unregistered Miner")

        let devices = [onlineValid, zeroRate, negativeRate, withError, reconnecting, noInfo, notInSnapshots]
        let snapshots: [UUID: MinerSnapshot] = [
            onlineValid.id: makeSnapshot(hashrate: 550.0),
            zeroRate.id: makeSnapshot(hashrate: 0.0),
            negativeRate.id: makeSnapshot(hashrate: -50.0),
            withError.id: makeSnapshot(hashrate: 600.0, error: "Connection timed out"),
            reconnecting.id: makeSnapshot(hashrate: 700.0, isReconnecting: true),
            noInfo.id: makeSnapshot(hashrate: nil)
        ]

        let slices = FleetHashrateShare.slices(devices: devices, snapshots: snapshots)

        #expect(slices.count == 1)
        #expect(slices[0].id == onlineValid.id)
        #expect(slices[0].name == "Online Miner")
        #expect(slices[0].hashrate == 550.0)
    }

    @Test func emptyFleetAndAllOfflineYieldEmptySlices() {
        let empty = FleetHashrateShare.slices(devices: [], snapshots: [:])
        #expect(empty.isEmpty)

        let dev = makeDevice(name: "Dead Miner")
        let offline = FleetHashrateShare.slices(
            devices: [dev],
            snapshots: [dev.id: makeSnapshot(hashrate: nil, error: "Offline")]
        )
        #expect(offline.isEmpty)
    }

    // MARK: - CPU Miner Exclusion

    @Test func cpuMinerExclusion() {
        let sha256Miner = makeDevice(name: "Bitaxe Gamma", kind: .espMiner)
        let cpuMiner = makeDevice(name: "MacBook XMRig", kind: .xmrig)

        let devices = [sha256Miner, cpuMiner]
        let snapshots: [UUID: MinerSnapshot] = [
            sha256Miner.id: makeSnapshot(hashrate: 600.0),
            cpuMiner.id: makeSnapshot(hashrate: 3000.0)
        ]

        let slices = FleetHashrateShare.slices(devices: devices, snapshots: snapshots)

        #expect(slices.count == 1)
        #expect(slices[0].id == sha256Miner.id)
        #expect(slices[0].name == "Bitaxe Gamma")
        #expect(slices[0].hashrate == 600.0)
        #expect(slices[0].fraction == 1.0)
    }

    // MARK: - Single Miner

    @Test func singleMinerProducesFullShare() {
        let dev = makeDevice(name: "Solo Miner")
        let devices = [dev]
        let snapshots: [UUID: MinerSnapshot] = [
            dev.id: makeSnapshot(hashrate: 450.0)
        ]

        let slices = FleetHashrateShare.slices(devices: devices, snapshots: snapshots)

        #expect(slices.count == 1)
        #expect(slices[0].id == dev.id)
        #expect(slices[0].name == "Solo Miner")
        #expect(slices[0].hashrate == 450.0)
        #expect(slices[0].fraction == 1.0)
        #expect(slices[0].percentage == 100.0)
        #expect(slices[0].percentageString == "100%")
        #expect(slices[0].colorIndex == 0)
    }

    // MARK: - Fractions Sum to 1

    @Test func fractionsSumToExactlyOneForTwoMiners() {
        let dev1 = makeDevice(name: "Miner A")
        let dev2 = makeDevice(name: "Miner B")

        let devices = [dev1, dev2]
        let snapshots: [UUID: MinerSnapshot] = [
            dev1.id: makeSnapshot(hashrate: 750.0),
            dev2.id: makeSnapshot(hashrate: 250.0)
        ]

        let slices = FleetHashrateShare.slices(devices: devices, snapshots: snapshots)

        #expect(slices.count == 2)
        #expect(slices[0].fraction == 0.75)
        #expect(slices[1].fraction == 0.25)

        let sum = slices.map(\.fraction).reduce(0.0, +)
        #expect(sum == 1.0)
    }

    @Test func fractionsSumToExactlyOneForThreeMiners() {
        let dev1 = makeDevice(name: "Miner 1")
        let dev2 = makeDevice(name: "Miner 2")
        let dev3 = makeDevice(name: "Miner 3")

        let devices = [dev1, dev2, dev3]
        let snapshots: [UUID: MinerSnapshot] = [
            dev1.id: makeSnapshot(hashrate: 100.0),
            dev2.id: makeSnapshot(hashrate: 100.0),
            dev3.id: makeSnapshot(hashrate: 100.0)
        ]

        let slices = FleetHashrateShare.slices(devices: devices, snapshots: snapshots)

        #expect(slices.count == 3)
        let sum = slices.map(\.fraction).reduce(0.0, +)
        #expect(sum == 1.0)
    }

    @Test func fractionsSumToExactlyOneForArbitraryFleet() {
        let rates = [680.0, 520.0, 480.0, 310.0, 150.0, 85.0, 22.0]
        let devices = rates.indices.map { index in
            makeDevice(name: "Miner \(index + 1)")
        }
        var snapshots: [UUID: MinerSnapshot] = [:]
        for (index, rate) in rates.enumerated() {
            snapshots[devices[index].id] = makeSnapshot(hashrate: rate)
        }

        let slices = FleetHashrateShare.slices(devices: devices, snapshots: snapshots)

        #expect(slices.count == rates.count)
        let sum = slices.map(\.fraction).reduce(0.0, +)
        #expect(sum == 1.0)

        // Verify descending order
        for i in 0..<(slices.count - 1) {
            #expect(slices[i].hashrate >= slices[i + 1].hashrate)
            #expect(slices[i].colorIndex == i)
        }
    }
}
