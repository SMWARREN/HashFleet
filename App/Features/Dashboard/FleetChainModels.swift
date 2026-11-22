import SwiftUI
import HashFleetCore

/// Freshness is source-specific. A successful fetch of an old provider cache is still old data.
enum ChainObservation {
    static func freshFleetRateHPS(devices: [MinerDevice], snapshots: [UUID: MinerSnapshot], now: Date, isDemo: Bool) -> Double? {
        var total: Double = 0
        guard !devices.isEmpty else { return nil }
        for device in devices {
            guard let snapshot = snapshots[device.id], !snapshot.isCached,
                snapshot.error == nil, let updated = snapshot.updatedAt, let info = snapshot.info,
                isDemo || (-60...FleetGlance.freshnessInterval * 3).contains(now.timeIntervalSince(updated)),
                let gh = FleetFormat.sensor(info, keys: "hashRate", "hashrate"), gh.isFinite, gh >= 0
            else { return nil }
            total += gh * 1e9
        }
        return total.isFinite ? total : nil
    }

    static func networkProblem<Value>(
        _ result: MiningDataResult<Value>?, difficulty: Double?, now: Date
    ) -> String? {
        guard let result else { return "Loading network data" }
        if let error = result.error {
            if case .http(let code) = error { return "Network source unavailable (HTTP \(code))" }
            return "Network source unavailable"
        }
        guard result.value != nil, let difficulty, difficulty.isFinite, difficulty > 0 else {
            return "Network difficulty not reported"
        }
        guard isFresh(result, now: now) else { return "Network data is stale" }
        return nil
    }

    static func isFresh<Value>(_ result: MiningDataResult<Value>?, now: Date) -> Bool {
        guard let result, result.value != nil, result.error == nil else { return false }
        return [result.fetchedAt, result.sourceTimestamp].compactMap { $0 }.allSatisfy {
            let age = now.timeIntervalSince($0)
            return age >= -60 && age <= 300
        }
    }

    static func nextHeight(_ tip: Int?) -> Int? {
        guard let tip, tip >= 0, tip < Int.max else { return nil }
        return tip + 1
    }

    static func chance(
        hashrateHPS: Double?,
        difficulty: Double?,
        fresh: Bool,
        duration: TimeInterval = 30 * 86400
    ) -> String {
        oddsReading(hashrateHPS: hashrateHPS, difficulty: difficulty, fresh: fresh, duration: duration).fullLabel
    }

    struct OddsReading {
        let summary: String
        var reciprocal: String?
        var fullLabel: String { reciprocal.map { summary + " · " + $0 } ?? summary }
        var compactLabel: String { reciprocal ?? summary }
    }

    static func oddsReading(
        hashrateHPS: Double?, difficulty: Double?, fresh: Bool, duration: TimeInterval
    ) -> OddsReading {
        guard fresh, let hashrateHPS, let difficulty,
            duration > 0, duration.isFinite,
            let estimate = SoloMiningMath.estimate(
                hashrateHPS: hashrateHPS,
                difficulty: difficulty,
                duration: duration
            )
        else {
            return OddsReading(summary: "Needs fresh readings")
        }
        let probability = estimate.probabilityAtLeastOne
        let percent = (probability * 100).formatted(.number.precision(.significantDigits(3))) + "%"
        guard probability > 0 else { return OddsReading(summary: percent) }
        let reciprocal = "1 in " + (1 / probability).formatted(.number.precision(.fractionLength(0)))
        return OddsReading(summary: percent, reciprocal: reciprocal)
    }
}

enum SoloOddsWindow: String, CaseIterable, Identifiable {
    case day
    case month
    case year

    var id: Self { self }

    var duration: TimeInterval {
        switch self {
        case .day: 24 * 60 * 60
        case .month: 30 * 24 * 60 * 60
        case .year: 365 * 24 * 60 * 60
        }
    }

    var shortLabel: String {
        switch self {
        case .day: "1d"
        case .month: "1mo"
        case .year: "1y"
        }
    }

    var title: String {
        switch self {
        case .day: "1-day"
        case .month: "30-day"
        case .year: "1-year"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .day: "1 day"
        case .month: "1 month"
        case .year: "1 year"
        }
    }
}

/// Groups only fresh, online miners whose active slot explicitly identifies a coin.
/// Missing rates make that group's estimate unavailable rather than silently undercounting it.
enum ActiveMiningCoins {
    struct Group: Identifiable, Equatable {
        var id: MiningPoolCoin { coin }
        let coin: MiningPoolCoin
        var miners: Int = 0
        var rateHPS: Double? = 0
    }

    static func groups(
        devices: [MinerDevice],
        snapshots: [UUID: MinerSnapshot],
        now: Date,
        isDemo: Bool
    ) -> [Group] {
        var groups: [MiningPoolCoin: Group] = [:]
        for device in devices {
            guard let snapshot = snapshots[device.id], snapshot.error == nil, !snapshot.isCached,
                let info = snapshot.info, let updated = snapshot.updatedAt
            else { continue }
            let age = now.timeIntervalSince(updated)
            guard isDemo || (age >= -60 && age <= FleetGlance.freshnessInterval * 3) else { continue }
            let active = ConfiguredMiningPool.resolve(info: info).filter { $0.isActive == true }
            guard active.count == 1, let coin = active.first?.coin else { continue }
            var group = groups[coin] ?? Group(coin: coin)
            group.miners += 1
            if let gh = FleetFormat.sensor(info, keys: "hashRate", "hashrate"),
                gh.isFinite, gh >= 0, let prior = group.rateHPS {
                let total = prior + gh * 1e9
                group.rateHPS = total.isFinite ? total : nil
            } else {
                group.rateHPS = nil
            }
            groups[coin] = group
        }
        return MiningPoolCoin.allCases.compactMap { groups[$0] }
    }
}

/// Active coins win. Configured coins are only a display fallback, never evidence of active mining.
enum FleetCoinVisibility {
    static let order: [MiningPoolCoin] = [.btc, .bch, .xec, .dgb, .bc2, .bch2]

    static func displayed(active: [MiningPoolCoin], configured: [MiningPoolCoin], custom: Set<MiningPoolCoin>?) -> [MiningPoolCoin] {
        let visible = custom ?? Set(active.isEmpty ? configured : active)
        return order.filter(visible.contains)
    }

    static func configured(devices: [MinerDevice], snapshots: [UUID: MinerSnapshot]) -> [MiningPoolCoin] {
        let coins = devices.flatMap { device in
            snapshots[device.id]?.info.map { ConfiguredMiningPool.resolve(info: $0).compactMap(\.coin) } ?? []
        }
        return displayed(active: [], configured: coins, custom: nil)
    }
}

enum FleetChainDataPolicy {
    /// Sample fixtures are local. Disabling public data must not erase the demo or enable
    /// any real fetch. Non-demo pages continue to require the explicit preference.
    static func canDisplay(isDemo: Bool, externalDataEnabled: Bool) -> Bool {
        isDemo || externalDataEnabled
    }
}
