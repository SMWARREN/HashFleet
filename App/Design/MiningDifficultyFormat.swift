import Foundation
import HashFleetCore

/// Formatter for mining difficulty values with SI abbreviation (K, M, G, T, P, E).
/// Preserves exact comparisons using `Decimal` and outputs 3 significant digit style
/// with trimmed trailing zeros (e.g. 392000000 -> 392M, 16384 -> 16.4K, 1050 -> 1.05K).
public enum MiningDifficultyFormat: Sendable {

    private struct Scale: Sendable {
        let threshold: Decimal
        let suffix: String
    }

    private static let scales: [Scale] = [
        Scale(threshold: Decimal(string: "1000000000000000000")!, suffix: "E"),
        Scale(threshold: Decimal(string: "1000000000000000")!, suffix: "P"),
        Scale(threshold: Decimal(string: "1000000000000")!, suffix: "T"),
        Scale(threshold: Decimal(string: "1000000000")!, suffix: "G"),
        Scale(threshold: Decimal(string: "1000000")!, suffix: "M"),
        Scale(threshold: Decimal(string: "1000")!, suffix: "K")
    ]

    // MARK: - Parsing

    /// Parses a raw difficulty representation (`JSONValue`) into an exact Decimal.
    /// Supports SI suffixes: K, M, G, T, P, E.
    /// Rejects negative values, non-finite values, booleans, arrays, objects, and malformed strings.
    /// Returns 0 for an explicit 0 representation.
    public static func parse(_ value: JSONValue?) -> Decimal? {
        guard let value else { return nil }
        switch value {
        case .integer(let int64):
            guard int64 >= 0 else { return nil }
            return Decimal(int64)
        case .unsignedInteger(let uint64):
            return Decimal(uint64)
        case .number(let double):
            return parse(double)
        case .string(let str):
            return parse(str)
        case .bool, .null, .array, .object:
            return nil
        }
    }

    /// Parses a finite non-negative Double difficulty into Decimal.
    /// Huge finite Doubles exceeding Decimal's representation range safely return `nil`.
    public static func parse(_ value: Double?) -> Decimal? {
        guard let value, value.isFinite, !value.isNaN, value >= 0 else { return nil }
        // Prefer string representation to avoid floating point artifact issues where possible
        if let dec = Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")),
            !dec.isNaN, dec >= 0 {
            return dec
        }
        let direct = Decimal(value)
        guard !direct.isNaN, direct >= 0 else { return nil }
        return direct
    }

    /// Parses an optional string containing a positive difficulty or 0,
    /// with optional SI multiplier suffix (K, M, G, T, P, E).
    public static func parse(_ rawString: String?) -> Decimal? {
        guard let rawString else { return nil }
        let trimmed = rawString.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty,
              trimmed != "Not reported" else {
            return nil
        }

        var numericPart = trimmed.uppercased()
        let multiplier = extractMultiplier(&numericPart)

        numericPart = numericPart.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !numericPart.isEmpty,
            numericPart.range(of: "^[0-9]+(?:\\.[0-9]+)?$", options: .regularExpression) != nil,
            let baseDecimal = Decimal(string: numericPart, locale: Locale(identifier: "en_US_POSIX"))
        else {
            return nil
        }

        guard !baseDecimal.isNaN, baseDecimal >= 0 else {
            return nil
        }
        let total = baseDecimal * multiplier
        guard !total.isNaN, total >= 0 else {
            return nil
        }
        return total
    }

    private static let suffixMultipliers: [(suffix: String, multiplier: Decimal)] = [
        ("K", 1_000),
        ("M", 1_000_000),
        ("G", 1_000_000_000),
        ("T", 1_000_000_000_000),
        ("P", 1_000_000_000_000_000),
        ("E", 1_000_000_000_000_000_000)
    ]

    private static func extractMultiplier(_ numericPart: inout String) -> Decimal {
        for entry in suffixMultipliers where numericPart.hasSuffix(entry.suffix) {
            numericPart.removeLast()
            return entry.multiplier
        }
        return 1
    }

    // MARK: - Short Format (3 Significant Digits)

    /// Short human-readable representation from an optional `JSONValue`.
    /// Returns `nil` if value is missing, null, negative, or malformed.
    /// Returns `"0"` for true zero.
    public static func short(_ value: JSONValue?) -> String? {
        guard let decimal = parse(value) else { return nil }
        return format(decimal)
    }

    /// Short human-readable representation from an optional `Double`.
    /// Returns `nil` if value is nil, non-finite, out of range, or negative.
    /// Returns `"0"` for true zero.
    public static func short(_ value: Double?) -> String? {
        guard let decimal = parse(value) else { return nil }
        return format(decimal)
    }

    /// Short human-readable representation from an optional `Decimal`.
    /// Returns `nil` if value is nil, NaN, or negative.
    /// Returns `"0"` for true zero.
    public static func short(_ value: Decimal?) -> String? {
        guard let value, !value.isNaN, value >= 0 else { return nil }
        return format(value)
    }

    /// Short human-readable representation from a raw `String?` difficulty (e.g. "392000000", "16384", "450.5K").
    /// Returns `nil` if value is nil, empty, or unparseable.
    /// Returns `"0"` for true zero.
    public static func short(_ rawString: String?) -> String? {
        guard let decimal = parse(rawString) else { return nil }
        return format(decimal)
    }

    // MARK: - Core Formatting Engine

    /// Formats a verified non-negative Decimal using up to 3 significant figures with trimmed trailing zeros.
    /// Handles boundary rounding across K, M, G, T, P, E cleanly (e.g. 999.6 -> 1K, 999.6M -> 1G).
    /// Strictly distinguishes true zero ("0") from small non-zero values (never rounds >0 down to "0").
    public static func format(_ decimal: Decimal) -> String {
        guard !decimal.isNaN, decimal >= 0 else { return "—" }
        if decimal == 0 { return "0" }
        // Below the compact decimal display range, retain Foundation's exact decimal
        // representation rather than letting a fixed fraction cap turn a share into zero.
        if decimal < Decimal(string: "0.00000000000001")! {
            return NSDecimalNumber(decimal: decimal).stringValue
        }

        for (index, scale) in scales.enumerated() where decimal >= scale.threshold {
            let scaled = decimal / scale.threshold
            return formatScaled(scaled, scaleIndex: index)
        }

        return formatScaled(decimal, scaleIndex: scales.count)
    }

    private static func formatScaled(_ scaled: Decimal, scaleIndex: Int) -> String {
        let hasSuffix = scaleIndex < scales.count
        let frac: Int
        if hasSuffix {
            // Abbreviated values (K, M, G, T, P, E) always show exactly two decimals
            // for a consistent, readable style (e.g. 11.20M, 392.00M, 1.00K).
            frac = 2
        } else if scaled >= 100 {
            frac = 0
        } else if scaled >= 10 {
            frac = 1
        } else if scaled >= 1 {
            frac = 2
        } else {
            // For values < 1 (e.g., fractional difficulties like 0.00123 or 0.0000001):
            // Count leading zeros after decimal point to preserve up to 3 significant digits.
            var temp = scaled
            var leadingZeros = 0
            while temp < 1 && leadingZeros < 14 {
                temp *= 10
                leadingZeros += 1
            }
            frac = leadingZeros + 2
        }

        var rounded = roundDecimal(scaled, scale: frac)

        // Guard against rounding a strictly positive value to true zero
        if rounded == 0 && scaled > 0 {
            // Fallback: round with sufficient precision to keep at least 1 significant digit
            var temp = scaled
            var leadingZeros = 0
            while temp < 1 && leadingZeros < 14 {
                temp *= 10
                leadingZeros += 1
            }
            rounded = roundDecimal(scaled, scale: leadingZeros)
        }

        // If rounding bumped across the scale boundary (e.g., 999.995 -> 1000)
        if rounded >= 1000 && scaleIndex > 0 {
            let nextScaleIndex = scaleIndex - 1
            let nextScaled = rounded / 1000
            return formatScaled(nextScaled, scaleIndex: nextScaleIndex)
        }

        let suffix = hasSuffix ? scales[scaleIndex].suffix : ""

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        // Abbreviated values keep a fixed two-decimal display; plain values trim trailing zeros.
        formatter.minimumFractionDigits = hasSuffix ? 2 : 0
        formatter.maximumFractionDigits = frac

        let formattedNumber = formatter.string(from: rounded as NSDecimalNumber) ?? "\(rounded)"
        return formattedNumber + suffix
    }

    private static func roundDecimal(_ decimal: Decimal, scale: Int) -> Decimal {
        var value = decimal
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, scale, .plain)
        return rounded
    }
}
