import Foundation
import HashFleetCore

/// Measured fleet energy for one local calendar day, integrated from saved power readings.
struct FleetDailyEnergy: Identifiable, Equatable, Sendable {
    let day: Date
    let kWh: Double
    /// Miner-minutes that had a power reading.
    let coveredMinerMinutes: Int
    /// Miner-minutes the day could have had (elapsed so far for today).
    let expectedMinerMinutes: Int
    /// Hours in this day so far (24 normally, 23 or 25 on clock changes, partial today).
    let hours: Double
    let isToday: Bool

    var id: Date { day }

    /// Share of the day backed by readings, 0...1.
    var coverage: Double {
        guard expectedMinerMinutes > 0 else { return 0 }
        return min(1, Double(coveredMinerMinutes) / Double(expectedMinerMinutes))
    }

    /// Readings cover enough of the day for the total to stand for the day's use.
    var isWellCovered: Bool { coverage >= Self.wellCoveredThreshold }
    static let wellCoveredThreshold = 0.9

    /// Average fleet power across the day, only when the day is well covered.
    var averageWatts: Double? {
        guard isWellCovered, hours > 0 else { return nil }
        let value = kWh * 1000 / hours
        return value.isFinite ? value : nil
    }
}

enum FleetDailyEnergyBuilder {
    /// Groups per-minute power into the last `days` local days, oldest first, today last.
    /// Each covered minute contributes its average watts for 60 seconds. Minutes with no reading
    /// add nothing, so a day with gaps reads low and is marked by its coverage.
    static func build(
        minutes: [MinerPowerMinute],
        minerCount: Int,
        days: Int = 7,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [FleetDailyEnergy] {
        guard days > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        let dayStarts: [Date] = (0..<days).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
        var watts: [Date: Double] = [:]
        var covered: [Date: Int] = [:]
        for minute in minutes where minute.averageWatts.isFinite && minute.averageWatts >= 0 {
            let day = calendar.startOfDay(for: minute.minuteStart)
            guard day >= (dayStarts.first ?? today), minute.minuteStart <= now else { continue }
            watts[day, default: 0] += minute.averageWatts
            covered[day, default: 0] += 1
        }
        return dayStarts.map { day in
            let isToday = day == today
            let end = isToday ? now : (calendar.date(byAdding: .day, value: 1, to: day) ?? day)
            let seconds = max(0, end.timeIntervalSince(day))
            let wattMinutes = watts[day] ?? 0
            return FleetDailyEnergy(
                day: day,
                kWh: wattMinutes * 60 / 3_600_000,
                coveredMinerMinutes: covered[day] ?? 0,
                expectedMinerMinutes: Int(seconds / 60) * max(0, minerCount),
                hours: seconds / 3600,
                isToday: isToday
            )
        }
    }
}

enum FleetEnergyComparison {
    /// Signed percentage change from `baseline` to `current`, nil without a usable baseline.
    static func percentChange(current: Double?, baseline: Double?) -> Double? {
        guard let current, let baseline, current.isFinite, baseline.isFinite, baseline > 0 else { return nil }
        let change = (current - baseline) / baseline * 100
        return change.isFinite ? change : nil
    }
}
