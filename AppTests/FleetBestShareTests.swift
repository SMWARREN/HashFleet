import Testing
import Foundation
import HashFleetCore
@testable import HashFleet

@Suite("Fleet best share tests")
struct FleetBestShareTests {

    // MARK: - Difficulty Parsing Tests

    @Test func parsesStandardIntegerDifficulties() {
        let candidate = FleetBestShareSummary.parseDifficulty("16384", minerName: "Miner A", isSession: false)
        #expect(candidate != nil)
        #expect(candidate?.decimalValue == 16384)
        #expect(candidate?.rawString == "16384")
        #expect(candidate?.displayString == "16.38K")
        #expect(candidate?.minerName == "Miner A")
        #expect(candidate?.isSession == false)
    }

    @Test func parsesExact392000000ToAbbreviatedDisplay() {
        let candidate = FleetBestShareSummary.parseDifficulty("392000000", minerName: "Miner X", isSession: false)
        #expect(candidate != nil)
        #expect(candidate?.decimalValue == 392_000_000)
        #expect(candidate?.rawString == "392000000")
        #expect(candidate?.displayString == "392.00M")
        #expect(candidate?.minerName == "Miner X")
    }

    @Test func parsesSISuffixDifficulties() {
        let kiloDifficulty = FleetBestShareSummary.parseDifficulty("450.5K", minerName: "M1", isSession: false)
        #expect(kiloDifficulty?.decimalValue == 450_500)
        #expect(kiloDifficulty?.rawString == "450.5K")
        #expect(kiloDifficulty?.displayString == "450.50K")

        let megaDifficulty = FleetBestShareSummary.parseDifficulty("3.45M", minerName: "M2", isSession: false)
        #expect(megaDifficulty?.decimalValue == 3_450_000)
        #expect(megaDifficulty?.rawString == "3.45M")
        #expect(megaDifficulty?.displayString == "3.45M")

        let gigaDifficulty = FleetBestShareSummary.parseDifficulty("1.25G", minerName: "M3", isSession: false)
        #expect(gigaDifficulty?.decimalValue == 1_250_000_000)
        #expect(gigaDifficulty?.rawString == "1.25G")
        #expect(gigaDifficulty?.displayString == "1.25G")

        let teraDifficulty = FleetBestShareSummary.parseDifficulty("2.1T", minerName: "M4", isSession: false)
        #expect(teraDifficulty?.decimalValue == 2_100_000_000_000)
        #expect(teraDifficulty?.rawString == "2.1T")
        #expect(teraDifficulty?.displayString == "2.10T")
    }

    @Test func parsesExactInt64BeyondDouble53BitLimit() {
        let big = "9007199254740993"  // 2^53 + 1
        let parsed = FleetBestShareSummary.parseDifficulty(big, minerName: "Bitaxe", isSession: false)
        #expect(parsed != nil)
        #expect(parsed?.decimalValue == Decimal(string: "9007199254740993"))
        #expect(parsed?.rawString == big)
        #expect(parsed?.displayString == "9.01P")
    }

    @Test func preservesZeroAndRejectsNegativeAndMalformedDifficulties() {
        let zero = FleetBestShareSummary.parseDifficulty("0", minerName: "M", isSession: false)
        #expect(zero?.decimalValue == 0)
        #expect(zero?.displayString == "0")
        #expect(zero?.rawString == "0")

        #expect(FleetBestShareSummary.parseDifficulty("-100", minerName: "M", isSession: false) == nil)
        #expect(FleetBestShareSummary.parseDifficulty("", minerName: "M", isSession: false) == nil)
        #expect(FleetBestShareSummary.parseDifficulty("   ", minerName: "M", isSession: false) == nil)
        #expect(FleetBestShareSummary.parseDifficulty("Not reported", minerName: "M", isSession: false) == nil)
        #expect(FleetBestShareSummary.parseDifficulty("NaN", minerName: "M", isSession: false) == nil)
        #expect(FleetBestShareSummary.parseDifficulty("Infinity", minerName: "M", isSession: false) == nil)
        #expect(FleetBestShareSummary.parseDifficulty("12garbage", minerName: "M", isSession: false) == nil)
        #expect(FleetBestShareSummary.parseDifficulty("abc", minerName: "M", isSession: false) == nil)
    }

    // MARK: - Fleet Aggregation Tests (Max never sum)

    @Test func selectsFleetMaxNeverSumsAcrossMiners() {
        let idA = UUID()
        let idB = UUID()
        let idC = UUID()

        let devA = MinerDevice(id: idA, name: "Miner A", address: "192.168.1.101")
        let devB = MinerDevice(id: idB, name: "Miner B", address: "192.168.1.102")
        let devC = MinerDevice(id: idC, name: "Miner C", address: "192.168.1.103")

        let snapA = MinerSnapshot(
            info: MinerInfo(raw: ["bestDiff": .string("1.5M"), "bestSessionDiff": .string("500K")]),
            error: nil,
            updatedAt: Date(),
            history: []
        )
        let snapB = MinerSnapshot(
            info: MinerInfo(raw: ["bestDiff": .string("2.8M"), "bestSessionDiff": .string("2.8M")]),
            error: nil,
            updatedAt: Date(),
            history: []
        )
        let snapC = MinerSnapshot(
            info: MinerInfo(raw: ["bestDiff": .string("950K"), "bestSessionDiff": .string("100K")]),
            error: nil,
            updatedAt: Date(),
            history: []
        )

        let devices = [devA, devB, devC]
        let snapshots = [idA: snapA, idB: snapB, idC: snapC]
        let summary = FleetBestShareSummary(devices: devices, snapshots: snapshots)

        #expect(summary.totalMinerCount == 3)
        #expect(summary.reportingMinerCount == 3)
        #expect(summary.offlineOrMissingCount == 0)

        // Maximum is 2.8M from Miner B, NOT 1.5M + 2.8M + 950K = 5.25M!
        #expect(summary.bestEver?.decimalValue == 2_800_000)
        #expect(summary.bestEver?.displayString == "2.80M")
        #expect(summary.bestEver?.minerName == "Miner B")

        // Session maximum is 2.8M from Miner B
        #expect(summary.bestSession?.decimalValue == 2_800_000)
        #expect(summary.bestSession?.displayString == "2.80M")
        #expect(summary.bestSession?.minerName == "Miner B")
    }

    @Test func offlineMinersAreExcludedFromBestCalculationAndCounted() {
        let idOnline = UUID()
        let idOffline = UUID()

        let devOnline = MinerDevice(id: idOnline, name: "Online Miner", address: "192.168.1.101")
        let devOffline = MinerDevice(id: idOffline, name: "Offline Miner", address: "192.168.1.102")

        let snapOnline = MinerSnapshot(
            info: MinerInfo(raw: ["bestDiff": .string("500K"), "bestSessionDiff": .string("250K")]),
            error: nil,
            updatedAt: Date(),
            history: []
        )
        let snapOffline = MinerSnapshot(
            info: MinerInfo(raw: ["bestDiff": .string("999G"), "bestSessionDiff": .string("999G")]),
            error: "Connection timed out",
            updatedAt: Date(),
            history: []
        )

        let devices = [devOnline, devOffline]
        let snapshots = [idOnline: snapOnline, idOffline: snapOffline]
        let summary = FleetBestShareSummary(devices: devices, snapshots: snapshots)

        #expect(summary.totalMinerCount == 2)
        #expect(summary.reportingMinerCount == 1)
        #expect(summary.offlineOrMissingCount == 1)

        // Offline miner's stale value is excluded
        #expect(summary.bestEver?.displayString == "500.00K")
        #expect(summary.bestEver?.minerName == "Online Miner")
    }

    @Test func persistedAllTimeHighSurvivesAResetLiveReading() {
        let id = UUID()
        let device = MinerDevice(id: id, name: "Reset Miner", address: "192.168.1.101")
        let snapshot = MinerSnapshot(
            info: MinerInfo(raw: ["bestDiff": .string("0"), "bestSessionDiff": .string("125K")]),
            error: nil,
            updatedAt: Date(),
            history: []
        )

        let summary = FleetBestShareSummary(
            devices: [device],
            snapshots: [id: snapshot],
            bestShareObservations: [
                id.uuidString: MinerBestShareObservation(bestDiff: "3.45M", bestSessionDiff: "125K")
            ]
        )

        #expect(summary.bestEver?.decimalValue == 3_450_000)
        #expect(summary.bestEver?.displayString == "3.45M")
        #expect(summary.bestEver?.minerName == "Reset Miner")
        #expect(summary.bestSession?.decimalValue == 125_000)
    }

    @Test func newerLiveAllTimeHighBeatsPersistedObservation() {
        let id = UUID()
        let device = MinerDevice(id: id, name: "Live Miner", address: "192.168.1.101")
        let snapshot = MinerSnapshot(
            info: MinerInfo(raw: ["bestDiff": .string("6M"), "bestSessionDiff": .string("6M")]),
            error: nil,
            updatedAt: Date(),
            history: []
        )

        let summary = FleetBestShareSummary(
            devices: [device],
            snapshots: [id: snapshot],
            bestShareObservations: [
                id.uuidString: MinerBestShareObservation(bestDiff: "5M", bestSessionDiff: "5M")
            ]
        )

        #expect(summary.bestEver?.decimalValue == 6_000_000)
        #expect(summary.bestEver?.rawString == "6M")
    }

    @Test func emptyFleetYieldsNilBestShares() {
        let summary = FleetBestShareSummary(devices: [], snapshots: [:])
        #expect(summary.bestEver == nil)
        #expect(summary.bestSession == nil)
        #expect(summary.reportingMinerCount == 0)
        #expect(summary.totalMinerCount == 0)
        #expect(summary.offlineOrMissingCount == 0)
    }

    @Test func detectsOnlyAStrictlyBetterPerMinerShareAndPrefersAllTime() {
        let device = MinerDevice(id: UUID(), name: "Workshop Gamma", address: "http://192.168.1.20")
        let previous = MinerInfo(raw: [
            "bestDiff": .string("1M"),
            "bestSessionDiff": .string("2M")
        ])
        let current = MinerInfo(raw: [
            "bestDiff": .string("2.5M"),
            "bestSessionDiff": .string("1.5M")
        ])

        let event = MinerBestShareEvent.detect(
            device: device,
            previous: previous,
            current: current,
            occurredAt: Date(timeIntervalSince1970: 42)
        )

        #expect(event?.deviceID == device.id)
        #expect(event?.minerName == "Workshop Gamma")
        #expect(event?.kind == .allTime)
        #expect(event?.displayValue == "2.50M")
        #expect(event?.rawValue == "2.5M")
    }

    @Test func doesNotCelebrateAFirstReadingOrAFlatOrLowerShare() {
        let device = MinerDevice(id: UUID(), name: "Workshop Gamma", address: "http://192.168.1.20")
        let current = MinerInfo(raw: ["bestDiff": .string("2M")])
        #expect(
            MinerBestShareEvent.detect(device: device, previous: nil, current: current, occurredAt: Date()) == nil
        )

        let previous = MinerInfo(raw: ["bestDiff": .string("2M")])
        let lower = MinerInfo(raw: ["bestDiff": .string("1M")])
        #expect(
            MinerBestShareEvent.detect(device: device, previous: previous, current: previous, occurredAt: Date())
                == nil
        )
        #expect(
            MinerBestShareEvent.detect(device: device, previous: previous, current: lower, occurredAt: Date()) == nil
        )
    }

    @Test func allTimeFloorPreventsResetOrFlashFromReCelebratingAnOldRecord() {
        // A reset/flash wipes NVS, so firmware bestDiff drops back toward 0 and then climbs.
        // With a persisted high-water mark, re-passing an old record must NOT fire again.
        let device = MinerDevice(id: UUID(), name: "Naja Duo", address: "http://192.0.2.226")

        // Fleet already recorded an all-time high of 5M.
        let floor = MiningDifficultyFormat.parse("5M")

        // After a flash, firmware reports a low baseline, then a reading that beats the last
        // reading (0 -> 3M) but is still below the 5M the fleet already celebrated.
        let postFlashBaseline = MinerBestShareObservation(bestDiff: "0", bestSessionDiff: "0")
        let climbingBackUp = MinerBestShareObservation(bestDiff: "3M", bestSessionDiff: "3M")

        let allTimeEvent = MinerBestShareEvent.detect(
            device: device,
            previous: postFlashBaseline,
            current: climbingBackUp,
            occurredAt: Date(),
            allTimeFloor: floor
        )
        // Session (0 -> 3M) is a legitimately new session record and may fire; all-time must not.
        #expect(allTimeEvent?.kind != .allTime)

        // Only once it truly beats the high-water mark does all-time fire again.
        let newRecord = MinerBestShareObservation(bestDiff: "6M", bestSessionDiff: "6M")
        let record = MinerBestShareEvent.detect(
            device: device,
            previous: climbingBackUp,
            current: newRecord,
            occurredAt: Date(),
            allTimeFloor: floor
        )
        #expect(record?.kind == .allTime)
        #expect(record?.displayValue == "6.00M")
    }

    @Test func sessionBestStillCelebratesAfterAResetIndependentOfAllTimeFloor() {
        // Session records legitimately restart each run and must remain celebratable even when
        // the all-time floor is high.
        let device = MinerDevice(id: UUID(), name: "Naja Duo", address: "http://192.0.2.226")
        let previous = MinerBestShareObservation(bestDiff: "5M", bestSessionDiff: "100K")
        let current = MinerBestShareObservation(bestDiff: "5M", bestSessionDiff: "800K")
        let event = MinerBestShareEvent.detect(
            device: device,
            previous: previous,
            current: current,
            occurredAt: Date(),
            allTimeFloor: MiningDifficultyFormat.parse("5M")
        )
        #expect(event?.kind == .session)
        #expect(event?.displayValue == "800.00K")
    }

    // MARK: - FleetBestShareSummary Empty & Offline & Persisted Branches

    @Test func emptyFleetBestShareSummaryProducesNoCandidates() {
        let summary = FleetBestShareSummary(devices: [], snapshots: [:])
        #expect(summary.totalMinerCount == 0)
        #expect(summary.reportingMinerCount == 0)
        #expect(summary.offlineOrMissingCount == 0)
        #expect(summary.bestEver == nil)
        #expect(summary.bestSession == nil)
    }

    @Test func offlineMinersExcludedFromBestShareSummary() {
        let device = MinerDevice(name: "Offline miner", address: "10.0.0.99")
        let errorSnapshot = MinerSnapshot(error: "Could not connect")
        let summary = FleetBestShareSummary(devices: [device], snapshots: [device.id: errorSnapshot])
        #expect(summary.totalMinerCount == 1)
        #expect(summary.reportingMinerCount == 0)
        #expect(summary.offlineOrMissingCount == 1)
        #expect(summary.bestEver == nil)
        #expect(summary.bestSession == nil)
    }

    @Test func persistedObservationUsedWhenHigherThanLiveDiff() {
        let device = MinerDevice(name: "Desk", address: "10.0.0.1")
        let snapshot = MinerSnapshot(
            info: MinerInfo(raw: ["bestDiff": .string("1M"), "bestSessionDiff": .string("500K")]),
            updatedAt: Date()
        )
        let observation = MinerBestShareObservation(bestDiff: "5M", bestSessionDiff: "200K")
        let summary = FleetBestShareSummary(
            devices: [device],
            snapshots: [device.id: snapshot],
            bestShareObservations: [device.id.uuidString: observation]
        )
        #expect(summary.totalMinerCount == 1)
        #expect(summary.reportingMinerCount == 1)
        #expect(summary.bestEver?.decimalValue == 5_000_000)
        #expect(summary.bestSession?.decimalValue == 500_000)
    }

    @Test func sessionDifficultySelectsMaxAcrossMiners() {
        let dev1 = MinerDevice(name: "Miner 1", address: "10.0.0.1")
        let dev2 = MinerDevice(name: "Miner 2", address: "10.0.0.2")

        let snap1 = MinerSnapshot(
            info: MinerInfo(raw: ["bestSessionDiff": .string("150K")]),
            updatedAt: Date()
        )
        let snap2 = MinerSnapshot(
            info: MinerInfo(raw: ["bestSessionDiff": .string("850K")]),
            updatedAt: Date()
        )

        let summary = FleetBestShareSummary(
            devices: [dev1, dev2],
            snapshots: [dev1.id: snap1, dev2.id: snap2]
        )
        #expect(summary.totalMinerCount == 2)
        #expect(summary.reportingMinerCount == 2)
        #expect(summary.bestSession?.minerName == "Miner 2")
        #expect(summary.bestSession?.decimalValue == 850_000)
    }
}
