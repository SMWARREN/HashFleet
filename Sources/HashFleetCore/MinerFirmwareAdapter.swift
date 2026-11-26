import Foundation

/// Detected miner identity returned by `MinerFirmwareAdapter.identifyHost`.
public struct MinerDetectedIdentity: Equatable, Hashable, Sendable {
    public let family: String
    public let host: String
    public let port: Int
    public let mac: String?
    public let model: String
    public let name: String
    public let info: MinerInfo

    public init(
        family: String,
        host: String,
        port: Int,
        mac: String? = nil,
        model: String,
        name: String,
        info: MinerInfo
    ) {
        self.family = family
        self.host = host
        self.port = port
        self.mac = mac
        self.model = model
        self.name = name
        self.info = info
    }
}

/// Unified firmware adapter that detects and polls all supported miner firmwares:
///
/// Detection order (porting MinerWatch `backend/discovery.py` + AxeForge `/api/status`):
/// 1. NMAxe via `GET /probe` (model starts with `"NM"`).
/// 2. BitForge via `deviceModel` containing `"bitforge"` or `chiptemp1` in `/api/system/info`.
/// 3. NerdQAxe / NerdOctaxe via `deviceModel` (`nerd`/`qaxe`/`octaxe`), `fanCount > 1`, or `currentA`.
/// 4. Bitaxe otherwise (including Bitfortun BS-1 if `deviceModel` identifies Bitfortun).
/// 5. AxeForge via `GET /api/status` (or `board` in payload), Harlo-OS via `/api/telemetry`,
///    then Hammer ThorOS via `GET /v2/miner/status` + `/v2/device/info`.
/// 6. Port 4028 cgminer, identified by `version` response keys: LuxOS (`lux`), then Braiins (`bos`/`braiins`), otherwise Canaan (`canaan`).
public struct MinerFirmwareAdapter: Sendable {
    public static let portHTTP = 80
    public static let portCgminer = 4028
    public typealias HTTPTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public let device: MinerDevice
    public let session: URLSession
    public let cgminerTransport: CgminerClient.Transport?

    public init(
        device: MinerDevice,
        session: URLSession = .shared,
        cgminerTransport: CgminerClient.Transport? = nil
    ) {
        self.device = device
        self.session = session
        self.cgminerTransport = cgminerTransport
    }

    // MARK: - Unified Info Read

    /// Reads and normalizes telemetry from `device` into a canonical `MinerInfo`.
    ///
    /// Routes directly to the saved `device.firmwareFamily` driver when known, or auto-detects
    /// across `/api/system/info`, `/api/status` (AxeForge), and port 4028 cgminer when needed.
    public func info() async throws -> MinerInfo {
        let baseURL = try device.validatedURL()
        let host = baseURL.host ?? device.address
        let explicitPort = baseURL.port
        let family = (device.firmwareFamily ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if ["luxos", "braiins", "canaan", "canaannano3", "cgminer"].contains(family) || explicitPort == Self.portCgminer {
            return try await pollCgminerInfo(host: host, port: explicitPort ?? Self.portCgminer, knownFamily: family)
        }

        if family == "axeforge" {
            if let statusInfo = try? await pollAxeForgeStatus(baseURL: baseURL, host: host) {
                return statusInfo
            }
            return try await pollHTTPSystemInfo(baseURL: baseURL, host: host, knownFamily: family)
        }

        if family == "thoros" {
            return try await pollThorOS(baseURL: baseURL, host: host)
        }

        if family == "harloos" {
            if let harloInfo = try? await pollHarloOS(baseURL: baseURL, host: host) {
                return harloInfo
            }
            return try await pollHTTPSystemInfo(baseURL: baseURL, host: host, knownFamily: family)
        }

        do {
            return try await pollHTTPSystemInfo(baseURL: baseURL, host: host, knownFamily: family)
        } catch let error as MinerAPIError {
            if case .http(let statusCode, _, _) = error,
               [404, 405, 501].contains(statusCode) {
                if let axeForgeInfo = try? await pollAxeForgeStatus(baseURL: baseURL, host: host) {
                    return axeForgeInfo
                }
                if let harloInfo = try? await pollHarloOS(baseURL: baseURL, host: host) {
                    return harloInfo
                }
                if let thorInfo = try? await pollThorOS(baseURL: baseURL, host: host) {
                    return thorInfo
                }
            }
            if let cgminerInfo = await cgminerFallbackInfo(host: host, family: family, httpError: error) {
                return cgminerInfo
            }
            throw error
        } catch {
            // ThorOS serves its HTML console for /api/system/info, which fails JSON decoding.
            if family.isEmpty, Self.httpFailureAllowsCgminerFallback(error),
               let thorInfo = try? await pollThorOS(baseURL: baseURL, host: host) {
                return thorInfo
            }
            if let cgminerInfo = await cgminerFallbackInfo(host: host, family: family, httpError: error) {
                return cgminerInfo
            }
            throw error
        }
    }

    /// Families known to serve only the HTTP API. They never fall back to cgminer port 4028.
    static let httpOnlyFamilies: Set<String> = [
        "bitaxe", "bitfortun", "nerdqaxe", "nerdoctaxe", "bitforge", "nmaxe", "warpaxe", "thoros"
    ]

    /// A saved miner with no known family and no HTTP miner API may be a cgminer device (Avalon
    /// Nano 3S, Braiins, LuxOS) answering only on TCP 4028. Try that port once before failing.
    /// Families already identified as HTTP firmware never take this path.
    private func cgminerFallbackInfo(host: String, family: String, httpError: Error) async -> MinerInfo? {
        guard !Self.httpOnlyFamilies.contains(family), !Task.isCancelled,
              Self.httpFailureAllowsCgminerFallback(httpError) else { return nil }
        let probe = CgminerClient(host: host, port: Self.portCgminer, timeout: 2.0, transport: cgminerTransport)
        guard let version = try? await probe.call("version"),
              Self.isCgminerVersionResponse(version) else { return nil }
        return try? await pollCgminerInfo(host: host, port: Self.portCgminer, knownFamily: "")
    }

    /// HTTP outcomes that mean "no miner HTTP API here": no listener, timeout, a missing route, or
    /// a body that is not a miner payload. Cancellation and invalid addresses never qualify.
    static func httpFailureAllowsCgminerFallback(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let apiError = error as? MinerAPIError {
            switch apiError {
            case .http(let statusCode, _, _): return [404, 405, 501].contains(statusCode)
            case .unrecognizedInfo, .invalidResponse: return true
            default: return false
            }
        }
        if let urlError = error as? URLError {
            return [
                .cannotConnectToHost, .timedOut, .networkConnectionLost,
                .badServerResponse, .cannotParseResponse, .zeroByteResource
            ].contains(urlError.code)
        }
        // A non-JSON body (for example an HTML page) fails JSON decoding.
        return error is DecodingError
    }

    // MARK: - HTTP Polling Helpers

    private func pollHTTPSystemInfo(baseURL: URL, host: String, knownFamily: String) async throws -> MinerInfo {
        let client = MinerAPIClient(device: device, session: session)
        let data = try await client.execute(.info)
        let decoded = try JSONDecoder().decode(MinerInfo.self, from: data)
        let raw = decoded.raw

        if Self.isNestedNmaxePayload(raw) || knownFamily == "nmaxe" {
            let sample = MinerHTTPDrivers.parseNmaxe(data: raw, host: host)
            let info = sample.toMinerInfo(preservingFlatRaw: true)
            guard MinerShapeValidator.isValidInfoShape(.object(info.raw)) else {
                throw MinerAPIError.unrecognizedInfo
            }
            return info
        }

        if MinerHTTPDrivers.isAxeForgeStatusShape(raw) {
            let sample = MinerHTTPDrivers.parseAxeForge(data: raw, host: host)
            let info = sample.toMinerInfo(preservingFlatRaw: true)
            guard MinerShapeValidator.isValidInfoShape(.object(info.raw)) else {
                throw MinerAPIError.unrecognizedInfo
            }
            return info
        }

        if MinerHTTPDrivers.isHarloOSShape(raw) || knownFamily == "harloos" {
            let sample = MinerHTTPDrivers.parseHarloOS(telemetry: raw, host: host)
            let info = sample.toMinerInfo(preservingFlatRaw: true)
            guard MinerShapeValidator.isValidInfoShape(.object(info.raw)) else {
                throw MinerAPIError.unrecognizedInfo
            }
            return info
        }

        guard MinerShapeValidator.isValidInfoShape(.object(raw)) else {
            throw MinerAPIError.unrecognizedInfo
        }

        let effectiveFamily = !knownFamily.isEmpty
            ? knownFamily
            : Self.classifyAxeOSPayload(raw: raw, asic: [:])

        var sample: MinerWatchSample
        switch effectiveFamily.lowercased() {
        case "warpaxe":
            sample = MinerHTTPDrivers.parseWarpAxe(data: raw, host: host)
        case "bitforge":
            sample = MinerHTTPDrivers.parseBitForge(data: raw, host: host)
        case "nerdqaxe", "nerdoctaxe":
            sample = MinerHTTPDrivers.parseNerdOctaxe(data: raw, host: host)
        case "bitfortun":
            sample = MinerHTTPDrivers.parseBitaxe(data: raw, host: host)
            sample.family = "bitfortun"
        default:
            sample = MinerHTTPDrivers.parseBitaxe(data: raw, host: host)
        }

        return sample.toMinerInfo(preservingFlatRaw: true)
    }

    private func pollAxeForgeStatus(baseURL: URL, host: String) async throws -> MinerInfo {
        let data = try await fetchHTTPJSONData(baseURL: baseURL, path: "/api/status", timeout: 15)
        let decoded = try JSONDecoder().decode(MinerInfo.self, from: data)
        guard MinerHTTPDrivers.isAxeForgeStatusShape(decoded.raw) else {
            throw MinerAPIError.unrecognizedInfo
        }
        let sample = MinerHTTPDrivers.parseAxeForge(data: decoded.raw, host: host)
        return sample.toMinerInfo(preservingFlatRaw: true)
    }

    private func pollCgminerInfo(host: String, port: Int, knownFamily: String) async throws -> MinerInfo {
        let cli = CgminerClient(host: host, port: port, timeout: 4.0, transport: cgminerTransport)
        let family: String
        if ["luxos", "braiins", "canaan", "canaannano3"].contains(knownFamily) {
            family = knownFamily
        } else {
            family = await MinerCgminerDrivers.fingerprint(client: cli) ?? "canaan"
        }

        let sample: MinerWatchSample
        switch family {
        case "luxos":
            sample = try await MinerCgminerDrivers.pollLuxos(client: cli)
        case "braiins":
            sample = try await MinerCgminerDrivers.pollBraiins(client: cli)
        default:
            sample = try await MinerCgminerDrivers.pollCanaan(client: cli, nano3: family == "canaannano3")
        }
        if sample.model == nil {
            var enriched = sample
            enriched.model = Self.defaultCgminerModel(for: family)
            if enriched.hostname == nil {
                enriched.hostname = Self.defaultCgminerName(for: family, host: host)
            }
            return enriched.toMinerInfo(preservingFlatRaw: false)
        }
        return sample.toMinerInfo(preservingFlatRaw: false)
    }

    internal func fetchHTTPJSONData(baseURL: URL, path: String, timeout: TimeInterval) async throws -> Data {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw MinerAPIError.invalidAddress(device.address)
        }
        components.path = path
        guard let url = components.url else {
            throw MinerAPIError.invalidAddress(device.address)
        }
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: timeout
        )
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MinerAPIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw MinerAPIError.http(
                statusCode: http.statusCode,
                message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                body: data
            )
        }
        return data
    }
}
