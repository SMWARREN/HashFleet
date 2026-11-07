import Foundation

/// A complete structural JSON representation. Integer cases avoid Double's 53-bit limit.
public enum JSONValue: Codable, Hashable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case integer(Int64)
    case unsignedInteger(UInt64)
    case bool(Bool)
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(UInt64.self) {
            self = .unsignedInteger(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .unsignedInteger(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var stringValue: String? {
        switch self {
        case .string(let value): value
        case .number(let value): String(value)
        case .integer(let value): String(value)
        case .unsignedInteger(let value): String(value)
        case .bool(let value): String(value)
        default: nil
        }
    }

    public var doubleValue: Double? {
        let result: Double?
        switch self {
        case .number(let value): result = value
        case .integer(let value): result = Double(value)
        case .unsignedInteger(let value): result = Double(value)
        case .string(let value): result = Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default: result = nil
        }
        return result.flatMap { $0.isFinite ? $0 : nil }
    }

    public var intValue: Int? {
        switch self {
        case .integer(let value): return Int(exactly: value)
        case .unsignedInteger(let value): return Int(exactly: value)
        case .string(let value):
            if let exact = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) { return exact }
        default: break
        }
        guard let number = doubleValue else { return nil }
        return Int(exactly: number.rounded(.towardZero))
    }

    public var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .string(let value):
            switch value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
            case "true", "1": return true
            case "false", "0": return false
            default: return nil
            }
        default:
            guard let number = doubleValue, number == 0 || number == 1 else { return nil }
            return number == 1
        }
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public subscript(key: String) -> JSONValue? { objectValue?[key] }

    /// Merges a firmware live update into an already complete object.
    ///
    /// Live telemetry frames are partial update envelopes. Objects merge recursively so a nested
    /// update cannot erase sibling fields from the complete HTTP snapshot, while arrays, scalars
    /// and explicit nulls replace the previous value as firmware specifies.
    public func merging(_ update: JSONValue) -> JSONValue {
        guard case .object(let current) = self,
            case .object(let delta) = update
        else {
            return update
        }

        var merged = current
        for (key, value) in delta {
            if let existing = merged[key] {
                merged[key] = existing.merging(value)
            } else {
                merged[key] = value
            }
        }
        return .object(merged)
    }

    /// The object-level form used by live telemetry consumers.
    public func merging(_ update: [String: JSONValue]) -> [String: JSONValue] {
        guard case .object(let merged) = merging(.object(update)) else { return update }
        return merged
    }

    public func prettyPrinted() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let encoded = try encoder.encode(self)
        guard let text = String(data: encoded, encoding: .utf8) else {
            throw CocoaError(.coderInvalidValue)
        }
        return text
    }
}
