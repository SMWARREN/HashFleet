import Foundation
import Observation
import HashFleetCore

@MainActor @Observable
final class FleetEnergySettings {
    static let rateKey = "app.hashfleet.energy.rate.v1"
    static let currencyKey = "app.hashfleet.energy.currency.v1"
    static let currencies = ["USD", "GBP", "EUR", "CAD", "AUD", "JPY", "CHF", "CNY"]
    private(set) var rate: Double?
    private(set) var currency: String
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let saved = defaults.object(forKey: Self.rateKey) as? Double
        rate = saved.flatMap { $0.isFinite && (0...10_000).contains($0) ? $0 : nil }
        let code = defaults.string(forKey: Self.currencyKey) ?? "USD"
        currency = Self.currencies.contains(code) ? code : "USD"
    }

    static func parseRate(_ text: String, locale: Locale = .current) throws -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = locale.decimalSeparator ?? "."
        guard separator == "." || !trimmed.contains(".") else { throw ValidationError.invalidRate }
        let normalized = String(trimmed.replacingOccurrences(of: separator, with: ".").map { character in
            if let digit = character.wholeNumberValue, (0...9).contains(digit) {
                return Character(String(digit))
            }
            return character
        })
        guard trimmed.count <= 32,
            normalized.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
            let value = Double(normalized), value.isFinite, (0...10_000).contains(value)
        else { throw ValidationError.invalidRate }
        return value
    }

    /// Keep enough significant digits to round-trip the saved Double without rounding a small tariff to zero.
    static func editableRate(_ value: Double, locale: Locale = .current) -> String {
        value.formatted(.number.locale(locale).grouping(.never).precision(.significantDigits(1...17)))
    }

    func save(rateText: String, currency: String, locale: Locale = .current) throws {
        let value = try Self.parseRate(rateText, locale: locale)
        guard Self.currencies.contains(currency) else { throw ValidationError.invalidCurrency }
        defaults.set(value, forKey: Self.rateKey)
        defaults.set(currency, forKey: Self.currencyKey)
        rate = value
        self.currency = currency
    }

    enum ValidationError: Error, LocalizedError {
        case invalidRate, invalidCurrency
        var errorDescription: String? {
            switch self {
            case .invalidRate: "Enter a rate between 0 and 10,000 per kWh, using your decimal separator with no thousands separators."
            case .invalidCurrency: "Choose a supported currency. No currency conversion happens."
            }
        }
    }
}

struct FleetEnergyEstimate: Equatable {
    let watts: Double?
    let reportingCount: Int
    let deviceCount: Int
    let isDemo: Bool

    var dailyKWh: Double? { watts.flatMap { Self.finite($0 * 24 / 1000) } }
    func dailyCost(rate: Double?) -> Double? {
        guard let rate, rate.isFinite, (0...10_000).contains(rate), let dailyKWh else { return nil }
        return Self.finite(dailyKWh * rate)
    }
    func monthlyCost(rate: Double?) -> Double? { dailyCost(rate: rate).flatMap { Self.finite($0 * 30) } }
    private static func finite(_ value: Double) -> Double? { value.isFinite && value >= 0 ? value : nil }

    @MainActor
    static func capture(store: FleetStore, at now: Date = .now) -> Self {
        let devices = store.visibleDevices
        let values = devices.compactMap { device -> Double? in
            guard let snapshot = store.snapshots[device.id], snapshot.error == nil, !snapshot.isCached,
                let observed = snapshot.powerObservedAt ?? snapshot.updatedAt, let info = snapshot.info else { return nil }
            let age = now.timeIntervalSince(observed)
            guard age.isFinite, age >= 0, age <= 120 else { return nil }
            return FleetMetricTotal.reading(info, keys: FleetTotals.powerKeys)
        }
        return Self(watts: values.isEmpty ? nil : finite(values.reduce(0, +)),
            reportingCount: values.count, deviceCount: devices.count, isDemo: store.isDemo)
    }
}
