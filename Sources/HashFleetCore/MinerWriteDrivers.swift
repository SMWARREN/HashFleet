import Foundation

/// Per-firmware write and control capability flags ported from MinerWatch's `MinerDriver`
/// base class plus AxeForge (`/api/settings`, `/api/restart`, `/api/identify`, `/api/pools`).
public struct MinerDriverCapabilities: Equatable, Hashable, Sendable {
    public let family: String
    public let canSetFan: Bool
    public let canSetFrequency: Bool
    public let canSetVoltage: Bool
    public let canSetWorkmode: Bool
    public let canRestart: Bool
    public let canPause: Bool
    public let canShutdown: Bool
    public let canSetPool: Bool
    public let canIdentify: Bool
    public let fanMinPct: Int

    public init(
        family: String,
        canSetFan: Bool = false,
        canSetFrequency: Bool = false,
        canSetVoltage: Bool = false,
        canSetWorkmode: Bool = false,
        canRestart: Bool = false,
        canPause: Bool = false,
        canShutdown: Bool = false,
        canSetPool: Bool = false,
        canIdentify: Bool = false,
        fanMinPct: Int = 0
    ) {
        self.family = family
        self.canSetFan = canSetFan
        self.canSetFrequency = canSetFrequency
        self.canSetVoltage = canSetVoltage
        self.canSetWorkmode = canSetWorkmode
        self.canRestart = canRestart
        self.canPause = canPause
        self.canShutdown = canShutdown
        self.canSetPool = canSetPool
        self.canIdentify = canIdentify
        self.fanMinPct = fanMinPct
    }

    public var isReadOnly: Bool {
        !canSetFan && !canSetFrequency && !canSetVoltage && !canSetWorkmode
            && !canRestart && !canPause && !canShutdown && !canSetPool && !canIdentify
    }

    public static func forFamily(_ rawFamily: String?, info: MinerInfo? = nil) -> MinerDriverCapabilities {
        let normalized = (rawFamily ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "nerdqaxe", "nerdoctaxe":
            return MinerDriverCapabilities(
                family: "nerdqaxe",
                canSetFan: true,
                canSetFrequency: true,
                canSetVoltage: true,
                canRestart: true,
                canPause: false,
                canShutdown: true,
                canSetPool: true,
                canIdentify: true
            )
        case "bitforge":
            let supportsPause = info == nil || info?.raw["miningPaused"] != nil
            return MinerDriverCapabilities(
                family: "bitforge",
                canSetFan: true,
                canSetFrequency: true,
                canSetVoltage: true,
                canRestart: true,
                canPause: supportsPause,
                canShutdown: false,
                canSetPool: true,
                canIdentify: true
            )
        case "nmaxe":
            return MinerDriverCapabilities(
                family: "nmaxe",
                canSetFan: true,
                canRestart: true
            )
        case "axeforge":
            return MinerDriverCapabilities(
                family: "axeForge",
                canSetFan: true,
                canSetFrequency: true,
                canSetVoltage: true,
                canRestart: true,
                canSetPool: true,
                canIdentify: true,
                fanMinPct: 20
            )
        case "harloos":
            return MinerDriverCapabilities(
                family: "harloOS",
                canSetFan: true,
                canSetFrequency: true,
                canSetVoltage: true,
                canRestart: true,
                canPause: true,
                canShutdown: true,
                canSetPool: true,
                fanMinPct: 20
            )
        case "warpaxe":
            return MinerDriverCapabilities(
                family: "warpAxe",
                canSetFan: true,
                canSetFrequency: true,
                canSetVoltage: true,
                canRestart: true,
                canPause: true,
                canShutdown: true,
                canSetPool: true
            )
        case "canaan":
            return MinerDriverCapabilities(
                family: "canaan",
                canSetFan: true,
                canSetFrequency: true,
                canSetVoltage: true,
                canSetWorkmode: true,
                canRestart: true,
                fanMinPct: 15
            )
        case "braiins", "luxos":
            return MinerDriverCapabilities(family: normalized)
        case "bitfortun":
            return MinerDriverCapabilities(
                family: "bitfortun",
                canSetFan: true,
                canSetFrequency: true,
                canSetVoltage: true,
                canRestart: true,
                canPause: true,
                canSetPool: true,
                canIdentify: true
            )
        default:
            return MinerDriverCapabilities(
                family: "bitaxe",
                canSetFan: true,
                canSetFrequency: true,
                canSetVoltage: true,
                canRestart: true,
                canPause: true,
                canSetPool: true,
                canIdentify: true
            )
        }
    }
}

/// Primary + fallback stratum pool configuration ported from MinerWatch's `PoolConfig`.
public struct MinerPoolConfig: Equatable, Hashable, Sendable {
    public var url: String
    public var port: Int
    public var user: String
    public var password: String
    public var tls: Bool
    public var cert: String
    public var fbURL: String
    public var fbPort: Int
    public var fbUser: String
    public var fbPassword: String
    public var fbTLS: Bool
    public var fbCert: String

    public init(
        url: String = "",
        port: Int = 3333,
        user: String = "",
        password: String = "x",
        tls: Bool = false,
        cert: String = "",
        fbURL: String = "",
        fbPort: Int = 3333,
        fbUser: String = "",
        fbPassword: String = "x",
        fbTLS: Bool = false,
        fbCert: String = ""
    ) {
        self.url = url
        self.port = port
        self.user = user
        self.password = password
        self.tls = tls
        self.cert = cert
        self.fbURL = fbURL
        self.fbPort = fbPort
        self.fbUser = fbUser
        self.fbPassword = fbPassword
        self.fbTLS = fbTLS
        self.fbCert = fbCert
    }

    public func toJSON() -> [String: JSONValue] {
        [
            "url": .string(url),
            "port": .integer(Int64(port)),
            "user": .string(user),
            "password": .string(password),
            "tls": .bool(tls),
            "cert": .string(cert),
            "fb_url": .string(fbURL),
            "fb_port": .integer(Int64(fbPort)),
            "fb_user": .string(fbUser),
            "fb_password": .string(fbPassword),
            "fb_tls": .bool(fbTLS),
            "fb_cert": .string(fbCert)
        ]
    }

    public static func fromJSON(_ data: [String: JSONValue]) -> MinerPoolConfig {
        MinerPoolConfig(
            url: data["url"]?.stringValue ?? "",
            port: MinerDriverParse.optInt(data["port"]) ?? 3333,
            user: data["user"]?.stringValue ?? "",
            password: data["password"]?.stringValue ?? "x",
            tls: MinerDriverParse.coerceFlag(data["tls"]),
            cert: data["cert"]?.stringValue ?? "",
            fbURL: data["fb_url"]?.stringValue ?? "",
            fbPort: MinerDriverParse.optInt(data["fb_port"]) ?? 3333,
            fbUser: data["fb_user"]?.stringValue ?? "",
            fbPassword: data["fb_password"]?.stringValue ?? "x",
            fbTLS: MinerDriverParse.coerceFlag(data["fb_tls"]),
            fbCert: data["fb_cert"]?.stringValue ?? ""
        )
    }
}

// MARK: - MinerFirmwareAdapter Write & Control Operations

extension MinerFirmwareAdapter {
    /// Returns the static driver capability flags for `device.firmwareFamily`.
    public var capabilities: MinerDriverCapabilities {
        MinerDriverCapabilities.forFamily(resolvedFamilyName)
    }

    public func capabilities(with info: MinerInfo?) -> MinerDriverCapabilities {
        MinerDriverCapabilities.forFamily(resolvedFamilyName, info: info)
    }

    internal var resolvedFamilyName: String {
        let raw = (device.firmwareFamily ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !raw.isEmpty { return raw }
        if (try? device.validatedURL())?.port == Self.portCgminer { return "canaan" }
        return "bitaxe"
    }

    // MARK: - High-Level MinerWatch Driver Write API

    /// Sets a manual fan speed percentage (0..100). Disables automatic fan control.
    /// For Canaan Avalon, values `< 15` switch back to automatic fan mode (`fan-spd,-1`).
    public func setFanSpeed(_ percent: Int) async throws -> Bool {
        let family = resolvedFamilyName
        switch family {
        case "canaan":
            if percent < 15 { return try await setAutoFan(true) }
            let clamped = max(15, min(100, percent))
            return try await callCanaanAscset("0,fan-spd,\(clamped)")
        case "nmaxe":
            let clamped = max(0, min(100, percent))
            let payload: JSONValue = .object([
                "fans": .array([
                    .object(["id": .integer(0), "auto": .bool(false), "speed": .integer(Int64(clamped))])
                ])
            ])
            return try await sendCustomHTTP(method: "PATCH", path: "/api/setting/preference", json: payload)
        case "bitforge":
            let clamped = max(0, min(100, percent))
            let payload: JSONValue = .object([
                "autofanspeed": .integer(0),
                "fanspeed": .integer(Int64(clamped)),
                "fanSpeed": .integer(Int64(clamped)),
                "manualFanSpeed": .integer(Int64(clamped))
            ])
            return try await sendCustomHTTP(method: "PATCH", path: "/api/system", json: payload)
        case "axeforge":
            let clamped = max(20, min(100, percent))
            let payload: JSONValue = .object([
                "fmode0": .integer(1),
                "fman0": .integer(Int64(clamped))
            ])
            return try await sendCustomHTTP(
                method: "POST", path: "/api/settings", json: payload, headers: ["X-AxeForge": "1"]
            )
        case "harloos":
            return try await setHarloOSFanSpeed(percent)
        case "braiins", "luxos":
            return false
        default:
            let clamped = max(0, min(100, percent))
            let payload: JSONValue = .object([
                "autofanspeed": .integer(0),
                "fanspeed": .integer(Int64(clamped)),
                "manualFanSpeed": .integer(Int64(clamped))
            ])
            return try await sendCustomHTTP(method: "PATCH", path: "/api/system", json: payload)
        }
    }

    /// Enables or disables automatic fan control.
    public func setAutoFan(_ enabled: Bool) async throws -> Bool {
        let family = resolvedFamilyName
        switch family {
        case "canaan":
            if !enabled { return try await setFanSpeed(50) }
            return try await callCanaanAscset("0,fan-spd,-1")
        case "nmaxe":
            let payload: JSONValue = .object([
                "fans": .array([
                    .object(["id": .integer(0), "auto": .bool(enabled)])
                ])
            ])
            return try await sendCustomHTTP(method: "PATCH", path: "/api/setting/preference", json: payload)
        case "axeforge":
            let payload: JSONValue = .object([
                "fmode0": .integer(enabled ? 0 : 1)
            ])
            return try await sendCustomHTTP(
                method: "POST", path: "/api/settings", json: payload, headers: ["X-AxeForge": "1"]
            )
        case "harloos":
            return try await setHarloOSAutoFan(enabled)
        case "braiins", "luxos":
            return false
        default:
            let payload: JSONValue = .object([
                "autofanspeed": .integer(enabled ? 1 : 0)
            ])
            return try await sendCustomHTTP(method: "PATCH", path: "/api/system", json: payload)
        }
    }

    /// Sets the target ASIC frequency in MHz.
    public func setFrequency(_ mhz: Double) async throws -> Bool {
        let family = resolvedFamilyName
        switch family {
        case "canaan":
            let clamped = max(200, min(1195, Int(mhz.rounded())))
            return try await callCanaanAscset("0,frequency,\(clamped):\(clamped):\(clamped):\(clamped)-0-0-0")
        case "axeforge":
            let payload: JSONValue = .object([
                "atune": .bool(false),
                "freq": .integer(Int64(mhz.rounded()))
            ])
            return try await sendCustomHTTP(
                method: "POST", path: "/api/settings", json: payload, headers: ["X-AxeForge": "1"]
            )
        case "harloos":
            return try await setHarloOSTuning(frequencyMHz: mhz, coreMV: nil)
        case "nmaxe", "braiins", "luxos":
            return false
        default:
            let freqVal: JSONValue = mhz.rounded() == mhz ? .integer(Int64(mhz)) : .number(mhz)
            let payload: JSONValue = .object(["frequency": freqVal])
            return try await sendCustomHTTP(method: "PATCH", path: "/api/system", json: payload)
        }
    }

    /// Sets the ASIC core voltage in millivolts.
    public func setVoltage(_ millivolts: Int) async throws -> Bool {
        let family = resolvedFamilyName
        switch family {
        case "canaan":
            return try await callCanaanAscset("0,voltage,\(millivolts)")
        case "axeforge":
            let payload: JSONValue = .object([
                "atune": .bool(false),
                "mv": .integer(Int64(millivolts))
            ])
            return try await sendCustomHTTP(
                method: "POST", path: "/api/settings", json: payload, headers: ["X-AxeForge": "1"]
            )
        case "harloos":
            return try await setHarloOSTuning(frequencyMHz: nil, coreMV: millivolts)
        case "nmaxe", "braiins", "luxos":
            return false
        default:
            let payload: JSONValue = .object(["coreVoltage": .integer(Int64(millivolts))])
            return try await sendCustomHTTP(method: "PATCH", path: "/api/system", json: payload)
        }
    }

    /// Sets the Canaan Avalon performance workmode (`0` = Low, `1` = Mid, `2` = High).
    public func setWorkmode(_ mode: Int) async throws -> Bool {
        guard resolvedFamilyName == "canaan", (0...2).contains(mode) else { return false }
        return try await callCanaanAscset("0,workmode,set,\(mode)")
    }

    /// Reboots/restarts the miner.
    public func restart() async throws -> Bool {
        let family = resolvedFamilyName
        switch family {
        case "canaan":
            let cli = try makeCgminerClient()
            _ = try await cli.call("ascset", parameter: "0,reboot,0")
            return true
        case "axeforge":
            return try await sendCustomHTTP(
                method: "POST", path: "/api/restart", json: nil, headers: ["X-AxeForge": "1"]
            )
        case "harloos":
            return try await sendCustomHTTP(method: "POST", path: "/api/reboot", json: nil)
        case "braiins", "luxos":
            return false
        default:
            return try await sendCustomHTTP(method: "POST", path: "/api/system/restart", json: nil)
        }
    }

    /// Pauses mining (or powers down into standby on NerdQAxe/Harlo-OS/WarpAxe).
    public func pause() async throws -> Bool {
        let family = resolvedFamilyName
        switch family {
        case "nerdqaxe", "nerdoctaxe":
            return try await shutdown()
        case "harloos":
            return try await sendCustomHTTP(method: "POST", path: "/api/asic/stop", json: nil)
        case "warpaxe":
            return try await sendCustomHTTP(method: "POST", path: "/api/v1/chips/off", json: nil)
        case "bitaxe", "bitfortun", "bitforge":
            return try await sendCustomHTTP(method: "POST", path: "/api/system/pause", json: nil)
        default:
            return false
        }
    }

    /// Resumes mining (or restarts from standby shutdown on NerdQAxe / starts ASIC on Harlo-OS & WarpAxe).
    public func resume() async throws -> Bool {
        let family = resolvedFamilyName
        switch family {
        case "nerdqaxe", "nerdoctaxe":
            return try await restart()
        case "harloos":
            return try await sendCustomHTTP(method: "POST", path: "/api/asic/start", json: nil)
        case "warpaxe":
            return try await sendCustomHTTP(method: "POST", path: "/api/v1/chips/on", json: nil)
        case "bitaxe", "bitfortun", "bitforge":
            return try await sendCustomHTTP(method: "POST", path: "/api/system/resume", json: nil)
        default:
            return false
        }
    }

    /// Powers down the ASIC and power stage on NerdQAxe (`POST /api/system/shutdown`),
    /// Harlo-OS (`POST /api/asic/stop`), or WarpAxe (`POST /api/v1/chips/off`).
    public func shutdown() async throws -> Bool {
        let family = resolvedFamilyName
        if family == "harloos" {
            return try await sendCustomHTTP(method: "POST", path: "/api/asic/stop", json: nil)
        }
        if family == "warpaxe" {
            return try await sendCustomHTTP(method: "POST", path: "/api/v1/chips/off", json: nil)
        }
        guard family == "nerdqaxe" || family == "nerdoctaxe" else { return false }
        return try await sendCustomHTTP(method: "POST", path: "/api/system/shutdown", json: nil)
    }

    /// Triggers the LED/screen identify signal on supported firmwares.
    public func identify() async throws -> Bool {
        let family = resolvedFamilyName
        switch family {
        case "axeforge":
            return try await sendCustomHTTP(
                method: "POST", path: "/api/identify", json: nil, headers: ["X-AxeForge": "1"]
            )
        case "bitaxe", "bitfortun", "nerdqaxe", "nerdoctaxe", "bitforge":
            return try await sendCustomHTTP(method: "POST", path: "/api/system/identify", json: nil)
        default:
            return false
        }
    }

    // MARK: - Pool Config Read/Write (MinerWatch PoolConfig + AxeForge /api/pools)

    public func readPoolConfig() async throws -> MinerPoolConfig {
        if resolvedFamilyName == "axeforge" {
            return try await readAxeForgePoolConfig()
        }
        if resolvedFamilyName == "harloos" {
            return try await readHarloOSPoolConfig()
        }
        let currentInfo = try await info()
        let raw = currentInfo.raw
        return MinerPoolConfig(
            url: raw["stratumURL"]?.stringValue ?? "",
            port: MinerDriverParse.optInt(raw["stratumPort"]) ?? 3333,
            user: raw["stratumUser"]?.stringValue ?? "",
            password: "x",
            tls: MinerDriverParse.coerceFlag(raw["stratumTLS"]),
            cert: raw["stratumCert"]?.stringValue ?? "",
            fbURL: raw["fallbackStratumURL"]?.stringValue ?? "",
            fbPort: MinerDriverParse.optInt(raw["fallbackStratumPort"]) ?? 3333,
            fbUser: raw["fallbackStratumUser"]?.stringValue ?? "",
            fbPassword: "x",
            fbTLS: MinerDriverParse.coerceFlag(raw["fallbackStratumTLS"]),
            fbCert: raw["fallbackStratumCert"]?.stringValue ?? ""
        )
    }

    public func setPool(_ config: MinerPoolConfig, restartAfter: Bool = true) async throws -> Bool {
        let family = resolvedFamilyName
        if family == "axeforge" {
            return try await writeAxeForgePoolConfig(config)
        }
        if family == "harloos" {
            return try await writeHarloOSPoolConfig(config)
        }
        guard ["bitaxe", "bitfortun", "nerdqaxe", "nerdoctaxe", "bitforge", "warpaxe"].contains(family) else {
            return false
        }
        var payload: [String: JSONValue] = [
            "stratumURL": .string(MinerDriverParse.stripScheme(config.url) ?? config.url),
            "stratumPort": .integer(Int64(config.port)),
            "stratumUser": .string(config.user),
            "stratumPassword": .string(config.password),
            "stratumTLS": .bool(config.tls)
        ]
        if !config.cert.isEmpty {
            payload["stratumCert"] = .string(config.cert)
        }
        if !config.fbURL.isEmpty {
            payload["fallbackStratumURL"] = .string(MinerDriverParse.stripScheme(config.fbURL) ?? config.fbURL)
            payload["fallbackStratumPort"] = .integer(Int64(config.fbPort))
            payload["fallbackStratumUser"] = .string(config.fbUser)
            payload["fallbackStratumPassword"] = .string(config.fbPassword)
            payload["fallbackStratumTLS"] = .bool(config.fbTLS)
            if !config.fbCert.isEmpty {
                payload["fallbackStratumCert"] = .string(config.fbCert)
            }
        }
        let ok = try await sendCustomHTTP(method: "PATCH", path: "/api/system", json: .object(payload))
        guard ok else { return false }
        if restartAfter {
            _ = try? await restart()
        }
        return true
    }

    public func activeSlot() async -> String? {
        guard let currentInfo = try? await info(),
              currentInfo.raw["isUsingFallbackStratum"] != nil else {
            return nil
        }
        let fb = MinerDriverParse.coerceFlag(currentInfo.raw["isUsingFallbackStratum"])
        return fb ? "fallback" : "primary"
    }

    public func scoreboard() async throws -> [MinerScoreboardEntry] {
        let data = try await execute(.scoreboard)
        return try JSONDecoder().decode([MinerScoreboardEntry].self, from: data)
    }

    // MARK: - Unified Endpoint Execution & Translation

    /// Executes a `MinerEndpoint` request, translating paths, methods, headers, and settings
    /// payload keys for non-Bitaxe firmwares (NerdQAxe, BitForge, NMAxe, AxeForge, Canaan cgminer).
    public func execute(
        _ endpoint: MinerEndpoint,
        body: Data? = nil,
        query: [URLQueryItem] = []
    ) async throws -> Data {
        let family = resolvedFamilyName
        switch family {
        case "canaan":
            return try await executeCanaanEndpoint(endpoint, body: body)
        case "braiins", "luxos":
            return try await executeReadOnlyCgminerEndpoint(endpoint)
        case "axeforge":
            return try await executeAxeForgeEndpoint(endpoint, body: body, query: query)
        case "harloos":
            return try await executeHarloOSEndpoint(endpoint, body: body, query: query)
        case "nmaxe":
            return try await executeNmaxeEndpoint(endpoint, body: body, query: query)
        case "bitforge":
            let translatedBody = endpoint == .settings ? Self.translateBitForgeSettingsBody(body) : body
            return try await MinerAPIClient(device: device, session: session)
                .execute(endpoint, body: translatedBody, query: query)
        case "nerdqaxe", "nerdoctaxe":
            return try await executeNerdQAxeEndpoint(endpoint, body: body, query: query)
        case "warpaxe":
            return try await executeWarpAxeEndpoint(endpoint, body: body, query: query)
        default:
            return try await MinerAPIClient(device: device, session: session)
                .execute(endpoint, body: body, query: query)
        }
    }
}
