import Foundation

public struct XMRigAPIClient: Sendable {
    public let device: MinerDevice
    /// The bearer token resolved from the device's keychain credential reference, if any.
    public let bearerToken: String?
    private let session: URLSession

    public init(device: MinerDevice, bearerToken: String? = nil, session: URLSession = .shared) {
        self.device = device
        self.bearerToken = bearerToken
        self.session = session
    }

    public func summary() async throws -> MinerInfo {
        do {
            let data = try await execute(path: "/2/summary")
            return try parseSummary(data)
        } catch let error as MinerAPIError {
            if case .http(let status, _, _) = error, status == 404 {
                let data = try await execute(path: "/1/summary")
                return try parseSummary(data)
            }
            throw error
        }
    }

    public func pause() async throws {
        try await executeJSONRPC(method: "pause")
    }

    public func resume() async throws {
        try await executeJSONRPC(method: "resume")
    }

    private func execute(path: String) async throws -> Data {
        let request = try buildRequest(method: "GET", path: path)
        let (data, response) = try await session.data(for: request, delegate: XMRigRedirectBlocker())
        guard let http = response as? HTTPURLResponse else { throw MinerAPIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw MinerAPIError.http(
                statusCode: http.statusCode,
                message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                body: data
            )
        }
        return data
    }

    private func executeJSONRPC(method: String) async throws {
        let payload: [String: AnyHashable] = [
            "id": 1,
            "jsonrpc": "2.0",
            "method": method
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        var request = try buildRequest(method: "POST", path: "/json_rpc")
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request, delegate: XMRigRedirectBlocker())
        guard let http = response as? HTTPURLResponse else { throw MinerAPIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw MinerAPIError.http(
                statusCode: http.statusCode,
                message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                body: data
            )
        }

        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data),
            case .object = json,
            json["jsonrpc"]?.stringValue == "2.0",
            json["id"] == .integer(1)
        else {
            throw MinerAPIError.invalidResponse
        }

        // Handle both the normal XMRig error envelope and code-only errors. A successful command
        // must still carry a result member, so HTML, empty bodies, `{}` and unrelated JSON never
        // become a false acknowledgement.
        if let error = json["error"], error != .null {
            let message = error["message"]?.stringValue
                ?? error["code"]?.stringValue
                ?? "XMRig JSON-RPC command failed."
            throw MinerAPIError.http(statusCode: http.statusCode, message: message, body: data)
        }
        guard let result = json["result"], case .object = result else {
            throw MinerAPIError.invalidResponse
        }
    }

    private func buildRequest(method: String, path: String) throws -> URLRequest {
        let base = try device.validatedURL()
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw MinerAPIError.invalidAddress(device.address)
        }
        components.path = path
        guard let url = components.url else { throw MinerAPIError.invalidAddress(device.address) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        if let token = bearerToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func parseSummary(_ data: Data) throws -> MinerInfo {
        let jsonValue = try JSONDecoder().decode(JSONValue.self, from: data)
        guard Self.isRecognizedSummary(jsonValue) else { throw MinerAPIError.unrecognizedInfo }
        var raw: [String: JSONValue] = [:]

        if let hashrate = jsonValue["hashrate"]?["total"]?.arrayValue?.first?.doubleValue {
            // XMRig reports H/s, MinerInfo expects GH/s
            raw["hashRate"] = .number(hashrate / 1_000_000_000.0)
        }
        if let results = jsonValue["results"] {
            if let accepted = Self.nonNegativeCounter(results["shares_good"]) {
                raw["sharesAccepted"] = .integer(Int64(accepted))
            }
            if let total = Self.nonNegativeCounter(results["shares_total"]),
                let accepted = Self.nonNegativeCounter(results["shares_good"]),
                accepted <= total {
                let subtraction = total.subtractingReportingOverflow(accepted)
                if !subtraction.overflow {
                    raw["sharesRejected"] = .integer(Int64(subtraction.partialValue))
                }
            }
            if let best = results["best"]?.arrayValue?.first {
                raw["bestDiff"] = best
            }
        }
        if let connection = jsonValue["connection"] {
            if let pool = connection["pool"] {
                raw["stratumURL"] = pool
            }
            if let uptime = connection["uptime"] {
                raw["uptimeSeconds"] = uptime
            }
        }
        if let paused = jsonValue["paused"] {
            raw["miningPaused"] = paused
        }
        if let version = jsonValue["version"] {
            raw["version"] = version
        }
        if let workerId = jsonValue["worker_id"] {
            raw["hostname"] = workerId
        }

        return MinerInfo(raw: raw)
    }

    private static func isRecognizedSummary(_ value: JSONValue) -> Bool {
        guard case .object = value else { return false }
        let hasHashrate = value["hashrate"]?["total"]?.arrayValue?.contains {
            if let number = $0.doubleValue { return number.isFinite }
            return false
        } == true
        let hasResults = value["results"]?.objectValue?.contains { key, raw in
            switch key {
            case "shares_good", "shares_total":
                return nonNegativeCounter(raw) != nil
            case "best":
                return raw.arrayValue?.contains { value in
                    guard let number = value.doubleValue else { return false }
                    return number.isFinite && number >= 0
                } == true
            default:
                return false
            }
        } == true
        let hasConnection = value["connection"]?.objectValue?.contains { key, raw in
            (key == "pool" && raw.stringValue?.isEmpty == false)
                || (key == "uptime" && raw.doubleValue != nil)
        } == true
        let hasIdentity = ["worker_id", "version"].contains {
            value[$0]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        let hasPaused = value["paused"]?.boolValue != nil
        let hasStructuralSummary = hasHashrate || hasResults || hasConnection
        // A version or worker label alone is not proof that the endpoint is XMRig. A paused-only
        // response is accepted only when it also carries an identity marker, which covers compact
        // summaries while rejecting arbitrary gateway JSON and `{}`.
        return hasStructuralSummary || (hasPaused && hasIdentity)
    }

    private static func nonNegativeCounter(_ value: JSONValue?) -> Int? {
        guard let value else { return nil }
        switch value {
        case .integer(let number):
            guard number >= 0 else { return nil }
            return Int(exactly: number)
        case .unsignedInteger(let number):
            return Int(exactly: number)
        case .number(let number):
            guard number.isFinite, number >= 0, number.rounded(.towardZero) == number else { return nil }
            return Int(exactly: number)
        case .string(let text):
            guard let number = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), number >= 0 else {
                return nil
            }
            return number
        case .object, .array, .bool, .null:
            return nil
        }
    }
}

private final class XMRigRedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
