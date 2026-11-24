import Foundation

// MARK: - Discovery & Host Identification (MinerWatch detection order)

extension MinerFirmwareAdapter {
    /// Humanizes a forge-os `deviceModel` identifier (e.g. `"BITFORGE_NANO"` -> `"BitForge Nano"`).
    public static func prettyBitForgeModel(_ deviceModel: String) -> String {
        let tokens = deviceModel
            .replacingOccurrences(of: "-", with: "_")
            .split(separator: "_")
            .map(String.init)
            .filter { !$0.isEmpty }
        let pretty = tokens.map { tok -> String in
            tok.lowercased() == "bitforge" ? "BitForge" : tok.capitalized
        }
        return pretty.isEmpty ? "BitForge" : pretty.joined(separator: " ")
    }

    public static func isNestedNmaxePayload(_ raw: [String: JSONValue]) -> Bool {
        guard raw["miner"]?.objectValue != nil else { return false }
        return raw["identity"]?.objectValue != nil
            || raw["asic"]?.objectValue != nil
            || raw["temps"]?.objectValue != nil
    }

    /// Classifies an HTTP `/api/system/info` payload (+ optional `/api/system/asic` payload
    /// or `GET /probe` payload) following MinerWatch's exact detection order.
    public static func classifyAxeOSPayload(
        raw: [String: JSONValue],
        asic: [String: JSONValue] = [:],
        probe: [String: JSONValue]? = nil
    ) -> String {
        if let probeModel = probe?["model"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           probeModel.uppercased().hasPrefix("NM") {
            return "nmaxe"
        }
        if isNestedNmaxePayload(raw) { return "nmaxe" }
        if MinerHTTPDrivers.isAxeForgeStatusShape(raw) { return "axeForge" }
        if MinerHTTPDrivers.isHarloOSShape(raw) { return "harloOS" }
        if MinerHTTPDrivers.isWarpAxeShape(raw) { return "warpAxe" }

        var deviceModel = (asic["deviceModel"]?.stringValue ?? raw["deviceModel"]?.stringValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if deviceModel.lowercased() == "invalid" { deviceModel = "" }
        let board = (raw["board"]?.stringValue ?? raw["boardVersion"]?.stringValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if board.localizedCaseInsensitiveContains("axeforge")
            || deviceModel.localizedCaseInsensitiveContains("axeforge") {
            return "axeForge"
        }
        if deviceModel.localizedCaseInsensitiveContains("bitfortun")
            || board.localizedCaseInsensitiveContains("bitfortun") {
            return "bitfortun"
        }
        if deviceModel.lowercased().contains("bitforge") || raw["chiptemp1"] != nil {
            return "bitforge"
        }

        let fanCountInt = MinerDriverParse.optInt(raw["fanCount"]) ?? 0
        let hasCurrentA = raw["currentA"] != nil && raw["currentA"] != .null
        let combined = "\(deviceModel) \(board) \(raw["hostname"]?.stringValue ?? "")".lowercased()
        let looksNerd = ["nerd", "qaxe", "octaxe"].contains(where: { combined.contains($0) })
        if looksNerd || fanCountInt > 1 || hasCurrentA {
            return "nerdqaxe"
        }
        return "bitaxe"
    }

    /// Evidence-based firmware family detector from an observed `MinerInfo` and optional `/api/system/asic` payload.
    /// Returns `nil` when there is no positive evidence of a specific firmware family.
    public static func detectedFamily(from info: MinerInfo?, asic: JSONValue? = nil) -> String? {
        guard let info else { return nil }
        let raw = info.raw
        let asicDict = asic?.objectValue ?? [:]

        if let explicit = raw["firmwareFamily"]?.stringValue,
           ["nmaxe", "bitforge", "nerdqaxe", "bitfortun", "axeForge", "harloOS", "warpAxe", "canaan", "canaannano3", "braiins", "luxos"]
            .contains(explicit) {
            return explicit
        }
        if isNestedNmaxePayload(raw) { return "nmaxe" }
        if MinerHTTPDrivers.isHarloOSShape(raw) { return "harloOS" }
        if MinerHTTPDrivers.isAxeForgeStatusShape(raw) { return "axeForge" }
        if MinerHTTPDrivers.isWarpAxeShape(raw) { return "warpAxe" }

        let classified = classifyAxeOSPayload(raw: raw, asic: asicDict)
        if classified != "bitaxe" {
            return classified
        }
        let evidence = [
            info.boardVersion,
            asicDict["deviceModel"]?.stringValue ?? "",
            raw["deviceModel"]?.stringValue ?? "",
            raw["board"]?.stringValue ?? "",
            info.hostname,
            info.version,
            info.axeOSVersion
        ]
        if evidence.contains(where: { $0.localizedCaseInsensitiveContains("bitaxe") }) {
            return "bitaxe"
        }
        return nil
    }

    /// Identifies a single host using MinerWatch's detection order plus AxeForge `/api/status`:
    /// 1. NMAxe via `GET /probe`
    /// 2. BitForge / NerdQAxe / Bitaxe via `GET /api/system/info` (+ `GET /api/system/asic`)
    /// 3. AxeForge via `GET /api/status`
    /// 4. Port 4028 cgminer (`version` keys: LuxOS -> Braiins -> Canaan)
    public static func identifyHost(
        _ host: String,
        timeout: TimeInterval = 2.0,
        httpTransport: HTTPTransport? = nil,
        cgminerTransport: CgminerClient.Transport? = nil
    ) async -> MinerDetectedIdentity? {
        let sendHTTP = makeHTTPTransport(injected: httpTransport, timeout: timeout)

        if let nmaxe = await identifyNmaxeViaProbe(host: host, timeout: timeout, transport: sendHTTP) {
            return nmaxe
        }
        if let axeOS = await identifyAxeOSViaInfo(host: host, timeout: timeout, transport: sendHTTP) {
            return axeOS
        }
        if let axeForge = await identifyAxeForgeViaStatus(host: host, timeout: timeout, transport: sendHTTP) {
            return axeForge
        }
        if let harloOS = await identifyHarloOSViaTelemetry(host: host, timeout: timeout, transport: sendHTTP) {
            return harloOS
        }
        if let cgIdentity = await identifyCgminer(host: host, timeout: timeout, transport: cgminerTransport) {
            return cgIdentity
        }
        return nil
    }

    private static func makeHTTPTransport(injected: HTTPTransport?, timeout: TimeInterval) -> HTTPTransport {
        if let injected { return injected }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)
        return { req in try await session.data(for: req) }
    }

    private static func identifyNmaxeViaProbe(
        host: String,
        timeout: TimeInterval,
        transport: HTTPTransport
    ) async -> MinerDetectedIdentity? {
        guard let probeDict = await fetchJSONObject(host: host, path: "/probe", timeout: timeout, transport: transport) else {
            return nil
        }
        let model = (probeDict["model"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard model.uppercased().hasPrefix("NM") else { return nil }
        let infoDict = await fetchJSONObject(host: host, path: "/api/system/info", timeout: timeout, transport: transport) ?? [:]
        var sample = MinerHTTPDrivers.parseNmaxe(data: infoDict, host: host)
        if sample.model == nil { sample.model = model }
        if sample.hostname == nil { sample.hostname = probeDict["hostname"]?.stringValue }
        let name = sample.hostname ?? model
        return MinerDetectedIdentity(
            family: "nmaxe",
            host: host,
            port: portHTTP,
            mac: nil,
            model: model,
            name: name.isEmpty ? "NMAxe \(host)" : name,
            info: sample.toMinerInfo(preservingFlatRaw: true)
        )
    }

    private static func identifyAxeOSViaInfo(
        host: String,
        timeout: TimeInterval,
        transport: HTTPTransport
    ) async -> MinerDetectedIdentity? {
        guard let infoDict = await fetchJSONObject(host: host, path: "/api/system/info", timeout: timeout, transport: transport) else {
            return nil
        }
        if isNestedNmaxePayload(infoDict) {
            let sample = MinerHTTPDrivers.parseNmaxe(data: infoDict, host: host)
            let model = sample.model ?? "NMAxe"
            return MinerDetectedIdentity(
                family: "nmaxe",
                host: host,
                port: portHTTP,
                mac: nil,
                model: model,
                name: sample.hostname ?? model,
                info: sample.toMinerInfo(preservingFlatRaw: true)
            )
        }
        guard MinerShapeValidator.isValidInfoShape(.object(infoDict)) else { return nil }
        let asicDict = await fetchJSONObject(host: host, path: "/api/system/asic", timeout: timeout, transport: transport) ?? [:]
        let family = classifyAxeOSPayload(raw: infoDict, asic: asicDict)
        var deviceModel = (asicDict["deviceModel"]?.stringValue ?? infoDict["deviceModel"]?.stringValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if deviceModel.lowercased() == "invalid" { deviceModel = "" }

        var sample: MinerWatchSample
        let model: String
        switch family {
        case "bitforge":
            sample = MinerHTTPDrivers.parseBitForge(data: infoDict, host: host)
            if !deviceModel.isEmpty {
                model = prettyBitForgeModel(deviceModel)
            } else if infoDict["ASICModel"]?.stringValue == "BM1370"
                && MinerDriverParse.optInt(infoDict["asicCount"]) == 2 {
                model = "BitForge Nano"
            } else {
                model = sample.model ?? "BitForge"
            }
        case "nerdqaxe":
            sample = MinerHTTPDrivers.parseNerdOctaxe(data: infoDict, host: host)
            model = !deviceModel.isEmpty ? deviceModel : (sample.model ?? "NerdOctaxe")
        case "warpAxe":
            sample = MinerHTTPDrivers.parseWarpAxe(data: infoDict, host: host)
            model = sample.model ?? (!deviceModel.isEmpty ? deviceModel : "WarpAxe")
        default:
            sample = MinerHTTPDrivers.parseBitaxe(data: infoDict, host: host)
            model = !deviceModel.isEmpty ? deviceModel : (sample.model ?? "Bitaxe")
        }
        sample.model = model
        return MinerDetectedIdentity(
            family: family,
            host: host,
            port: portHTTP,
            mac: sample.mac,
            model: model,
            name: sample.hostname ?? model,
            info: sample.toMinerInfo(preservingFlatRaw: true)
        )
    }

    private static func identifyAxeForgeViaStatus(
        host: String,
        timeout: TimeInterval,
        transport: HTTPTransport
    ) async -> MinerDetectedIdentity? {
        guard let statusDict = await fetchJSONObject(host: host, path: "/api/status", timeout: timeout, transport: transport),
              MinerHTTPDrivers.isAxeForgeStatusShape(statusDict) else {
            return nil
        }
        let sample = MinerHTTPDrivers.parseAxeForge(data: statusDict, host: host)
        let model = sample.model ?? "AxeForge"
        return MinerDetectedIdentity(
            family: "axeForge",
            host: host,
            port: portHTTP,
            mac: sample.mac,
            model: model,
            name: sample.hostname ?? model,
            info: sample.toMinerInfo(preservingFlatRaw: true)
        )
    }

    public static func identifyCgminer(
        host: String,
        port: Int = portCgminer,
        timeout: TimeInterval = 2.0,
        transport: CgminerClient.Transport? = nil
    ) async -> MinerDetectedIdentity? {
        let cli = CgminerClient(host: host, port: port, timeout: timeout, transport: transport)
        guard let versionResp = try? await cli.call("version"),
              isCgminerVersionResponse(versionResp) else { return nil }
        var family = MinerCgminerDrivers.fingerprint(versionResponse: versionResp)
        if family == "canaan", let estats = try? await cli.call("estats"), MinerCgminerDrivers.estatsSaysNano3(estats) {
            family = "canaannano3"
        }
        let sample: MinerWatchSample?
        switch family {
        case "luxos": sample = try? await MinerCgminerDrivers.pollLuxos(client: cli)
        case "braiins": sample = try? await MinerCgminerDrivers.pollBraiins(client: cli)
        default: sample = try? await MinerCgminerDrivers.pollCanaan(client: cli, nano3: family == "canaannano3")
        }

        let defModel = defaultCgminerModel(for: family)
        let defName = defaultCgminerName(for: family, host: host)
        guard var resolved = sample, resolved.online else {
            let fallbackSample = MinerWatchSample(
                family: family, host: host, online: true, model: defModel, hostname: defName
            )
            return MinerDetectedIdentity(
                family: family, host: host, port: port, mac: nil,
                model: defModel, name: defName, info: fallbackSample.toMinerInfo()
            )
        }
        let model = resolved.model ?? defModel
        let name = resolved.model ?? defName
        resolved.model = model
        if resolved.hostname == nil { resolved.hostname = name }
        return MinerDetectedIdentity(
            family: family, host: host, port: port, mac: resolved.mac,
            model: model, name: name, info: resolved.toMinerInfo()
        )
    }

    /// A genuine cgminer `version` reply has a non-empty `VERSION` section naming the API or miner
    /// (`API`, `CGMiner`, `BOSminer`, `LUXminer`, `PROD`, `MODEL`). Any other text that happens to
    /// answer on port 4028 is not a miner and must not become an "Avalon" result.
    public static func isCgminerVersionResponse(_ response: [String: JSONValue]) -> Bool {
        guard let section = MinerDriverParse.sectionArray(response, key: "VERSION").first,
              !section.isEmpty else { return false }
        let markers = ["api", "cgminer", "bmminer", "bosminer", "luxminer", "miner", "prod", "model", "lversion"]
        return section.keys.contains { key in
            let lower = key.lowercased()
            return markers.contains { lower.contains($0) }
        }
    }

    public static func defaultCgminerModel(for family: String) -> String {
        switch family {
        case "luxos": "LuxOS"
        case "braiins": "BMM101"
        case "canaan": "Avalon"
        case "canaannano3": "Avalon Nano 3"
        default: family.capitalized
        }
    }

    public static func defaultCgminerName(for family: String, host: String) -> String {
        family == "braiins" ? "Braiins BMM101" : "\(defaultCgminerModel(for: family)) \(host)"
    }

    internal static func fetchJSONObject(
        host: String,
        path: String,
        timeout: TimeInterval,
        transport: HTTPTransport
    ) async -> [String: JSONValue]? {
        let base = host.contains("://") ? host : "http://\(host)"
        guard var components = URLComponents(string: base) else { return nil }
        components.path = path
        guard let url = components.url else { return nil }
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: timeout
        )
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await transport(request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 else {
            return nil
        }
        if let contentType = http.value(forHTTPHeaderField: "Content-Type"),
           !contentType.lowercased().contains("json") {
            return nil
        }
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .object(let dict) = json,
              !dict.isEmpty else {
            return nil
        }
        return dict
    }
}
