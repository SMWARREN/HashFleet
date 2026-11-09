import Foundation

/// Only this minimal, device-local configuration is shared with the bundled extension.
/// Cloud installation credentials and raw firmware objects must never be stored here.
public struct FleetScheduledCheckTarget: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var baseURL: URL
    public var expectedMAC: String

    public init(id: UUID, name: String, baseURL: URL, expectedMAC: String) {
        self.id = id
        self.name = Self.safeName(name)
        self.baseURL = baseURL
        self.expectedMAC = Self.normalizedMAC(expectedMAC) ?? expectedMAC
    }

    public var isValid: Bool {
        Self.validBaseURL(baseURL) && Self.normalizedMAC(expectedMAC) != nil
            && name == Self.safeName(name) && !name.isEmpty
    }

    public static func safeName(_ value: String) -> String {
        let clean = String(String.UnicodeScalarView(value.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
        }.prefix(64))).trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "Miner" : clean
    }

    /// Accept exactly twelve hex digits or six consistently separated hex octets.
    /// The pin prevents accidental identity confusion, not a malicious LAN impersonator.
    public static func normalizedMAC(_ value: String) -> String? {
        let parts: [Substring]
        if value.contains(":") {
            parts = value.split(separator: ":", omittingEmptySubsequences: false)
        } else if value.contains("-") {
            parts = value.split(separator: "-", omittingEmptySubsequences: false)
        } else {
            parts = []
        }
        let raw: String
        if parts.isEmpty { raw = value } else {
            guard parts.count == 6, parts.allSatisfy({ $0.utf8.count == 2 }) else { return nil }
            raw = parts.joined()
        }
        guard raw.utf8.count == 12,
              raw.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              let first = UInt8(raw.prefix(2), radix: 16), first & 1 == 0,
              raw != String(repeating: "0", count: 12) else { return nil }
        return raw.uppercased()
    }

    /// Deliberately excludes DNS, IPv6, public/loopback/link-local addresses and URL ambiguity.
    /// No discovery or resolving a hostname onto a different network is attempted.
    public static func validBaseURL(_ url: URL) -> Bool {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = c.scheme, ["http", "https"].contains(scheme),
              let host = c.host, c.user == nil, c.password == nil,
              c.query == nil, c.fragment == nil, c.path.isEmpty || c.path == "/",
              c.port.map({ (1...65535).contains($0) }) ?? true else { return false }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        var octets: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }),
                  let n = Int(part), (0...255).contains(n), String(n) == part else { return false }
            octets.append(n)
        }
        let isPrivate = octets[0] == 10
            || (octets[0] == 172 && (16...31).contains(octets[1]))
            || (octets[0] == 192 && octets[1] == 168)
        let port = c.port.map { ":\($0)" } ?? ""
        return isPrivate && url.absoluteString == "\(scheme)://\(host)\(port)\(c.path)"
    }
}

public struct FleetScheduledCheckConfiguration: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var targets: [FleetScheduledCheckTarget]
    public init(enabled: Bool = false, targets: [FleetScheduledCheckTarget] = []) {
        self.enabled = enabled
        self.targets = targets
    }
    public static let disabled = Self()
    var isValid: Bool {
        targets.count <= 64 && targets.allSatisfy(\.isValid)
            && Set(targets.map(\.id)).count == targets.count && (!enabled || !targets.isEmpty)
    }
    public func target(id: UUID) -> FleetScheduledCheckTarget? {
        guard enabled, isValid else { return nil }
        return targets.first { $0.id == id }
    }
}

public enum FleetScheduledCheckStorage {
    public static let key = "app.hashfleet.scheduled-check.configuration.v1"
    public static let maximumBytes = 131_072

    /// Explicit nil is unavailable, never an instruction to fall back to production defaults.
    public static func load(defaults: UserDefaults?) -> FleetScheduledCheckConfiguration {
        guard let data = defaults?.data(forKey: key), data.count <= maximumBytes,
              let value = try? JSONDecoder().decode(FleetScheduledCheckConfiguration.self, from: data),
              value.enabled, value.isValid else { return .disabled }
        return value
    }

    public static func write(_ value: FleetScheduledCheckConfiguration, defaults: UserDefaults?) {
        guard let defaults else { return }
        guard value.enabled, value.isValid,
              let data = try? JSONEncoder().encode(value), data.count <= maximumBytes else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}

/// Only these four scheduling fields are interpreted. The push cannot supply a URL or command.
public struct FleetScheduledCheckRequest: Decodable, Equatable, Sendable {
    public let deviceID: UUID
    public let version: Int
    public let issuedAt: TimeInterval
    public let requestID: String
    enum CodingKeys: String, CodingKey {
        case deviceID = "app.hashfleet.deviceID"
        case version = "app.hashfleet.checkVersion"
        case issuedAt = "app.hashfleet.checkIssuedAt"
        case requestID = "app.hashfleet.checkRequestID"
    }
    public init(deviceID: UUID, version: Int = 1, issuedAt: TimeInterval, requestID: String) {
        self.deviceID = deviceID
        self.version = version
        self.issuedAt = issuedAt
        self.requestID = requestID
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .deviceID)
        guard let uuid = UUID(uuidString: id), uuid.uuidString.lowercased() == id else {
            throw DecodingError.dataCorruptedError(forKey: .deviceID, in: c, debugDescription: "Invalid device ID")
        }
        deviceID = uuid
        version = try c.decode(Int.self, forKey: .version)
        issuedAt = try c.decode(Double.self, forKey: .issuedAt)
        requestID = try c.decode(String.self, forKey: .requestID)
    }
    public func isValid(now: Date = .now) -> Bool {
        let age = now.timeIntervalSince1970 - issuedAt
        return version == 1 && issuedAt.isFinite && (-120...600).contains(age)
            && (1...64).contains(requestID.utf8.count)
            && requestID.utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
            }
    }
    public static func parse(_ data: Data, now: Date = .now) -> Self? {
        guard data.count <= 4096, let value = try? JSONDecoder().decode(Self.self, from: data),
              value.isValid(now: now) else { return nil }
        return value
    }
}

public struct FleetScheduledCheckReading: Equatable, Sendable {
    public let hashRateGHs: Double?
    public let temperatureC: Double?
    public let powerW: Double?
    public let sharesAccepted: UInt64?
    public let sharesRejected: UInt64?

    public init(hashRateGHs: Double? = nil, temperatureC: Double? = nil, powerW: Double? = nil,
                sharesAccepted: UInt64? = nil, sharesRejected: UInt64? = nil) {
        self.hashRateGHs = Self.bounded(hashRateGHs, 0...1e12)
        self.temperatureC = Self.bounded(temperatureC, -40...150)
        self.powerW = Self.bounded(powerW, 0...1e6)
        self.sharesAccepted = sharesAccepted.flatMap { $0 <= 9_000_000_000_000_000 ? $0 : nil }
        self.sharesRejected = sharesRejected.flatMap { $0 <= 9_000_000_000_000_000 ? $0 : nil }
    }
    private static func bounded(_ value: Double?, _ range: ClosedRange<Double>) -> Double? {
        value.flatMap { $0.isFinite && range.contains($0) ? $0 : nil }
    }
    public var body: String {
        let locale = Locale(identifier: "en_US_POSIX")
        var parts: [String] = []
        if let rate = hashRateGHs {
            parts.append(rate >= 1000 ? String(format: "%.2f TH/s", locale: locale, rate / 1000)
                : String(format: "%.1f GH/s", locale: locale, rate))
        }
        if let temp = temperatureC { parts.append(String(format: "%.1f °C", locale: locale, temp)) }
        if let power = powerW { parts.append(String(format: "%.1f W", locale: locale, power)) }
        if let accepted = sharesAccepted { parts.append("\(accepted) accepted shares") }
        if let rejected = sharesRejected { parts.append("\(rejected) rejected shares") }
        return parts.isEmpty ? "Reached the saved miner, but summary measurements were unavailable."
            : "Just checked: " + parts.joined(separator: " · ")
    }
}

public struct FleetScheduledCheckPresentation: Equatable, Sendable {
    public let title: String
    public let body: String
    public init(title: String, body: String) { self.title = title; self.body = body }
    public static let unavailable = Self(title: "Scheduled miner check",
        body: "Current readings are unavailable. Open Hash Fleet on your miners' network to check.")
}

public enum FleetScheduledCheckRunner {
    /// Selection is checked both before and after I/O. Cancellation or any failure yields no reading.
    public static func perform(
        request: FleetScheduledCheckRequest,
        configuration: @Sendable () -> FleetScheduledCheckConfiguration,
        now: @Sendable () -> Date = { .now },
        read: @Sendable (FleetScheduledCheckTarget) async throws -> FleetScheduledCheckReading
    ) async -> FleetScheduledCheckPresentation {
        guard !Task.isCancelled, request.isValid(now: now()),
              let target = configuration().target(id: request.deviceID) else { return .unavailable }
        do {
            let reading = try await read(target)
            try Task.checkCancellation()
            guard request.isValid(now: now()), configuration().target(id: request.deviceID) == target else {
                return .unavailable
            }
            return .init(title: target.name, body: reading.body)
        } catch { return .unavailable }
    }
}
