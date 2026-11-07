//
//  FleetDailyEnergyTests.swift
//  MacAppTests
//
//  Energy page "Measured use": daily kWh from saved per-minute power, coverage and change tags.
//

import Foundation
import Testing
import HashFleetCore
@testable import HashFleetMac

@Suite("Measured daily energy")
struct FleetDailyEnergyTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    /// Noon on 2026-11-07 New York.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 12))! }

    private func minutes(day offset: Int, count: Int, watts: Double, miner: String = "a") -> [MinerPowerMinute] {
        let start = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
        return (0..<count).map {
            MinerPowerMinute(minerId: miner, minuteStart: start.addingTimeInterval(Double($0) * 60), averageWatts: watts)
        }
    }

    @Test func fullDayAtConstantPowerIntegratesToKWh() {
        // 100 W for all 1,440 minutes of yesterday = 2.4 kWh.
        let days = FleetDailyEnergyBuilder.build(
            minutes: minutes(day: -1, count: 1440, watts: 100), minerCount: 1, now: now, calendar: calendar
        )
        #expect(days.count == 7)
        let yesterday = days[5]
        #expect(abs(yesterday.kWh - 2.4) < 0.0001)
        #expect(yesterday.isWellCovered)
        #expect(abs((yesterday.averageWatts ?? 0) - 100) < 0.001)
        #expect(days[6].isToday)
    }

    @Test func gapsAreNotCountedAsIdleAndMarkTheDayPartial() {
        let days = FleetDailyEnergyBuilder.build(
            minutes: minutes(day: -1, count: 720, watts: 100), minerCount: 1, now: now, calendar: calendar
        )
        let yesterday = days[5]
        #expect(abs(yesterday.kWh - 1.2) < 0.0001)
        #expect(abs(yesterday.coverage - 0.5) < 0.001)
        #expect(!yesterday.isWellCovered)
        #expect(yesterday.averageWatts == nil)
    }

    @Test func coverageCountsEveryMiner() {
        // Two miners expected, only one reported all day: half covered.
        let days = FleetDailyEnergyBuilder.build(
            minutes: minutes(day: -1, count: 1440, watts: 50), minerCount: 2, now: now, calendar: calendar
        )
        #expect(abs(days[5].coverage - 0.5) < 0.001)
    }

    @Test func todayUsesElapsedTimeOnly() {
        // Noon: 720 elapsed minutes, all covered.
        let days = FleetDailyEnergyBuilder.build(
            minutes: minutes(day: 0, count: 720, watts: 100), minerCount: 1, now: now, calendar: calendar
        )
        let today = days[6]
        #expect(today.expectedMinerMinutes == 720)
        #expect(today.isWellCovered)
        #expect(abs(today.hours - 12) < 0.001)
    }

    @Test func readingsOutsideTheWindowAndInvalidWattsAreIgnored() {
        var input = minutes(day: -9, count: 10, watts: 100)
        input.append(MinerPowerMinute(minerId: "a", minuteStart: now.addingTimeInterval(-60), averageWatts: -5))
        input.append(MinerPowerMinute(minerId: "a", minuteStart: now.addingTimeInterval(-120), averageWatts: .nan))
        input.append(MinerPowerMinute(minerId: "a", minuteStart: now.addingTimeInterval(600), averageWatts: 100))
        let days = FleetDailyEnergyBuilder.build(minutes: input, minerCount: 1, now: now, calendar: calendar)
        #expect(days.allSatisfy { $0.coveredMinerMinutes == 0 && $0.kWh == 0 })
    }

    @Test func percentChange() {
        #expect(FleetEnergyComparison.percentChange(current: 110, baseline: 100) == 10)
        #expect(FleetEnergyComparison.percentChange(current: 90, baseline: 100) == -10)
        #expect(FleetEnergyComparison.percentChange(current: 5, baseline: 0) == nil)
        #expect(FleetEnergyComparison.percentChange(current: nil, baseline: 100) == nil)
        #expect(FleetEnergyComparison.percentChange(current: 5, baseline: nil) == nil)
    }

    @Test func changeTagText() {
        #expect(FleetEnergyChangeTag.text(12.34) == "+12.3%")
        #expect(FleetEnergyChangeTag.text(-4) == "−4%")
        #expect(FleetEnergyChangeTag.text(0.01) == "0%")
    }

    @MainActor
    @Test func databaseAveragesPowerPerMinute() async {
        let database = MinerTelemetryDatabase(inMemory: true)
        let base = Date(timeIntervalSince1970: 1_799_999_940) // a whole minute
        for (offset, watts) in [(0.0, 10.0), (20, 20), (40, 30), (65, 50)] {
            database.recordReading(
                minerId: "m1",
                timestamp: base.addingTimeInterval(offset),
                reading: MinerReadingInput(power: watts)
            )
        }
        database.recordReading(minerId: "other", timestamp: base, reading: MinerReadingInput(power: 999))
        await database.flushReadings()
        let result = await database.getPowerMinutes(
            minerIds: ["m1"], since: base.addingTimeInterval(-1), until: base.addingTimeInterval(120)
        )
        #expect(result.count == 2)
        #expect(result.first?.averageWatts == 20)
        #expect(result.last?.averageWatts == 50)
        #expect(result.allSatisfy { $0.minerId == "m1" })
    }
}
