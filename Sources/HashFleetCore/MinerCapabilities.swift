import Foundation

/// Status of probing a single firmware endpoint capability.
public enum MinerProbeStatus: Hashable, Sendable {
    /// Endpoint has not been probed yet.
    case notChecked

    /// Endpoint returned a valid, recognized response conforming to firmware schema.
    case supported

    /// Endpoint is explicitly not supported or not implemented by the firmware (HTTP 404, 405, 501).
    case unsupported(statusCode: Int)

    /// Probe failed due to network, transport, authentication (401/403), rate-limiting (429),
    /// server error (500/502/503), invalid JSON, or unrecognized payload shape.
    /// This represents an environmental or protocol failure, never hardware non-support.
    case failed(message: String)

    public var isSupported: Bool {
        if case .supported = self { return true }
        return false
    }

    public var isUnsupported: Bool {
        if case .unsupported = self { return true }
        return false
    }

    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// Consolidated capability report produced by checking read-only endpoints.
public struct MinerCapabilityReport: Hashable, Sendable {
    /// Decoded system info if supported, nil otherwise.
    public var info: MinerInfo?

    /// Decoded raw ASIC payload if supported, nil otherwise.
    public var asic: JSONValue?

    /// Probe status for `GET /api/system/info`.
    public var infoStatus: MinerProbeStatus

    /// Probe status for `GET /api/system/asic`.
    public var asicStatus: MinerProbeStatus

    /// Timestamp when capability check occurred.
    public var checkedAt: Date

    public init(
        info: MinerInfo? = nil,
        asic: JSONValue? = nil,
        infoStatus: MinerProbeStatus = .notChecked,
        asicStatus: MinerProbeStatus = .notChecked,
        checkedAt: Date = Date()
    ) {
        self.info = info
        self.asic = asic
        self.infoStatus = infoStatus
        self.asicStatus = asicStatus
        self.checkedAt = checkedAt
    }

    /// True if system info is supported.
    public var isInfoSupported: Bool { infoStatus == .supported }

    /// True if ASIC configuration endpoint is supported.
    public var isASICSupported: Bool { asicStatus == .supported }

    /// True if one endpoint is supported while the other is not supported or failed.
    public var isPartiallySupported: Bool {
        (infoStatus == .supported && asicStatus != .supported)
            || (infoStatus != .supported && asicStatus == .supported)
    }

    /// True if both Info and ASIC endpoints are supported.
    public var isFullySupported: Bool {
        infoStatus == .supported && asicStatus == .supported
    }
}

/// Evaluates payload structure against known AxeOS response shapes and validates
/// that recognized keys contain meaningful expected-type values rather than merely checking key existence.
public enum MinerShapeValidator: Sendable {
    /// Validates whether a decoded JSONValue represents a recognized `GET /api/system/info` payload.
    /// Requires an object containing at least one recognized key with a valid typed value.
    public static func isValidInfoShape(_ json: JSONValue) -> Bool {
        guard case .object(let dict) = json, !dict.isEmpty else { return false }

        // Recognized string fields: must be non-empty strings.
        let stringKeys: Set<String> = [
            "hostname", "fullHostname", "mdnsHostname", "version", "axeOSVersion",
            "boardVersion", "deviceModel", "ASICModel", "asicModel",
            "stratumURL", "poolURL", "idfVersion", "macAddr"
        ]
        if hasNonEmptyString(dict, keys: stringKeys) { return true }

        // Recognized numeric/metric fields: must parse to a valid, finite Double.
        let numericKeys: Set<String> = [
            "hashRate", "hashrate", "expectedHashrate", "hashRate_1m", "hashRate_10m", "hashRate_1h",
            "power", "voltage", "nominalVoltage", "current",
            "frequency", "actualFrequency", "coreVoltage", "coreVoltageActual",
            "temp", "temp2", "vrTemp", "fanspeed", "fanSpeed", "fanrpm", "fanRpm", "fan2rpm",
            "sharesAccepted", "sharesRejected", "sharesPending", "uptimeSeconds",
            "wifiRSSI", "wifiRssi", "freeHeap", "freeHeapInternal", "freeHeapSpiram",
            "errorPercentage", "temptarget"
        ]
        if numericKeys.contains(where: { dict[$0]?.doubleValue != nil }) { return true }

        // Difficulty metrics: may be non-empty string (e.g. "1.25G") or finite number.
        let diffKeys: Set<String> = ["bestDiff", "bestSessionDiff", "poolDifficulty"]
        if diffKeys.contains(where: {
            guard let val = dict[$0] else { return false }
            return val.doubleValue != nil || nonEmptyString(val)
        }) { return true }

        // Recognized array fields: must be a JSON array.
        if diffOrArray(dict, keys: ["pools", "partitions"]) { return true }

        return false
    }

    /// Validates whether a decoded JSONValue represents a recognized `GET /api/system/asic` payload.
    /// Requires an object containing at least one recognized key with a valid typed value.
    public static func isValidASICShape(_ json: JSONValue) -> Bool {
        guard case .object(let dict) = json, !dict.isEmpty else { return false }

        // Recognized string fields: must be non-empty string.
        let stringKeys: Set<String> = ["ASICModel", "asicModel", "deviceModel", "swarmColor"]
        if hasNonEmptyString(dict, keys: stringKeys) { return true }

        // Recognized numeric options/defaults: must be finite number.
        let numericKeys: Set<String> = ["defaultFrequency", "defaultVoltage", "asicCount", "chipCount"]
        if numericKeys.contains(where: { dict[$0]?.doubleValue != nil }) { return true }

        // Recognized option arrays: must be JSON array.
        return diffOrArray(dict, keys: ["frequencyOptions", "voltageOptions"])
    }
}

extension MinerShapeValidator {
    private static func nonEmptyString(_ value: JSONValue?) -> Bool {
        guard case .string(let str) = value else { return false }
        return !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func hasNonEmptyString(_ dict: [String: JSONValue], keys: Set<String>) -> Bool {
        keys.contains(where: { nonEmptyString(dict[$0]) })
    }

    private static func diffOrArray(_ dict: [String: JSONValue], keys: [String]) -> Bool {
        keys.contains { key in
            guard let val = dict[key], case .array = val else { return false }
            return true
        }
    }
}

/// Readonly capability probe. Dispatches exactly one GET `/api/system/info` and one
/// GET `/api/system/asic` using the injected client/session.
public struct MinerCapabilityProbe: Sendable {
    public let client: MinerAPIClient

    public init(client: MinerAPIClient) {
        self.client = client
    }

    public init(device: MinerDevice, session: URLSession = .shared) {
        self.init(client: MinerAPIClient(device: device, session: session))
    }

    /// Probes miner endpoints and compiles a capability report.
    ///
    /// Respects task cancellation (throws CancellationError without converting to failed or unsupported).
    public func check() async throws -> MinerCapabilityReport {
        try Task.checkCancellation()

        async let infoProbe = probeInfo()
        async let asicProbe = probeASIC()

        let (info, infoStatus) = try await infoProbe
        let (asic, asicStatus) = try await asicProbe

        try Task.checkCancellation()

        return MinerCapabilityReport(
            info: info,
            asic: asic,
            infoStatus: infoStatus,
            asicStatus: asicStatus,
            checkedAt: Date()
        )
    }

    private func probeInfo() async throws -> (MinerInfo?, MinerProbeStatus) {
        let (json, status) = try await probeJSON(
            endpoint: .info,
            shape: MinerShapeValidator.isValidInfoShape,
            notJSON: "Info response was not valid JSON.",
            notObject: "Info response was not a JSON object.",
            wrongShape: "Unrecognized /api/system/info response shape."
        )
        guard let json, case .object(let object) = json else { return (nil, status) }
        return (MinerInfo(raw: object), status)
    }

    private func probeASIC() async throws -> (JSONValue?, MinerProbeStatus) {
        try await probeJSON(
            endpoint: .asic,
            shape: MinerShapeValidator.isValidASICShape,
            notJSON: "ASIC response was not valid JSON.",
            notObject: "ASIC response was not a JSON object.",
            wrongShape: "Unrecognized /api/system/asic response shape."
        )
    }

    /// One endpoint probe with shape validation; all transport errors map to a bounded status.
    /// Cancellation always rethrows, never masquerades as a failure.
    private func probeJSON(
        endpoint: MinerEndpoint,
        shape: (JSONValue) -> Bool,
        notJSON: String,
        notObject: String,
        wrongShape: String
    ) async throws -> (JSONValue?, MinerProbeStatus) {
        try Task.checkCancellation()
        do {
            let data = try await client.execute(endpoint)
            try Task.checkCancellation()
            let json: JSONValue
            do {
                json = try JSONDecoder().decode(JSONValue.self, from: data)
            } catch {
                return (nil, .failed(message: notJSON))
            }
            guard case .object = json else { return (nil, .failed(message: notObject)) }
            guard shape(json) else { return (nil, .failed(message: wrongShape)) }
            return (json, .supported)
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            if let urlError = error as? URLError, urlError.code == .cancelled { throw CancellationError() }
            if let status = Self.probeErrorStatus(error) { return (nil, status) }
            return (nil, .failed(message: Self.sanitizedErrorMessage(error.localizedDescription)))
        }
    }

    /// Maps transport errors to probe statuses, or nil when only a sanitized message fits.
    private static func probeErrorStatus(_ error: any Error) -> MinerProbeStatus? {
        if error is CancellationError { return nil }
        if let urlError = error as? URLError, urlError.code == .cancelled { return nil }
        if let apiError = error as? MinerAPIError {
            switch apiError {
            case .http(let statusCode, _, _):
                return Self.isUnsupportedStatus(statusCode)
                    ? .unsupported(statusCode: statusCode)
                    : .failed(message: Self.sanitizedHTTPMessage(statusCode: statusCode))
            case .invalidAddress:
                return .failed(message: "Invalid miner address.")
            case .invalidResponse:
                return .failed(message: "The miner returned a non-HTTP response.")
            default:
                return .failed(message: Self.sanitizedErrorMessage(apiError.localizedDescription))
            }
        }
        return nil
    }

    public static func isUnsupportedStatus(_ statusCode: Int) -> Bool {
        statusCode == 404 || statusCode == 405 || statusCode == 501
    }

    private static func sanitizedHTTPMessage(statusCode: Int) -> String {
        // Never echo even a short response body: credentials need not contain a recognizable keyword.
        "HTTP \(statusCode): \(HTTPURLResponse.localizedString(forStatusCode: statusCode))"
    }

    private static func sanitizedErrorMessage(_ message: String) -> String {
        // Transport descriptions can embed addresses or server-provided text. Keep summaries generic.
        "Could not reach the miner. Check its address, network access and Wi-Fi, then retry."
    }
}
