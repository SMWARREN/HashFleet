import Foundation

/// Port of MinerWatch's port-4028 cgminer drivers (`CanaanDriver`, `BraiinsDriver`, and shared helpers).
public enum MinerCgminerDrivers {
    private static let chipModelRules: [([String], String)] = [
        (["s21", "t21"], "BM1370"),
        (["s19 xp", "s19j xp", "t19 xp", "s19k"], "BM1366"),
        (["s19j pro", "s19a", "s19j"], "BM1362"),
        (["s19", "s19 pro", "t19"], "BM1397"),
        (["s9"], "BM1387")
    ]

    public static func chipModel(for model: String?) -> String? {
        guard let model = model?.lowercased(), !model.isEmpty else { return nil }
        for (needles, chip) in chipModelRules where needles.contains(where: { model.contains($0) }) {
            return chip
        }
        return nil
    }

    /// Identifies the cgminer firmware family from the raw `version` response keys:
    /// 1. Any key matching `lux` -> `"luxos"`
    /// 2. Any key matching `bos` or `braiins` -> `"braiins"`
    /// 3. `MODEL=nano3` / `PROD=Avalonnano` / `SWTYPE=MM318` (original Avalon Nano 3) -> `"canaannano3"`
    /// 4. Otherwise -> `"canaan"`
    public static func fingerprint(versionResponse: [String: JSONValue]) -> String {
        let vList = MinerDriverParse.sectionArray(versionResponse, key: "VERSION")
        guard let vDict = vList.first, !vDict.isEmpty else {
            return "canaan"
        }
        let keysLower = vDict.keys.map { $0.lowercased() }
        if keysLower.contains(where: { $0.contains("lux") }) {
            return "luxos"
        }
        if keysLower.contains(where: { $0.contains("bos") || $0.contains("braiins") }) {
            return "braiins"
        }
        if isAvalonNano3(versionSection: vDict) {
            return "canaannano3"
        }
        return "canaan"
    }

    /// Classifies firmware text as original Nano 3 (true), Nano 3s (false) or unknown (nil).
    /// `nano3s` is checked first because it contains the `nano3` prefix.
    public static func nano3Marker(_ text: String) -> Bool? {
        let blob = text.lowercased().filter { ![" ", "-", "_"].contains($0) }
        if blob.contains("nano3s") { return false }
        if blob.contains("nano3") || blob.contains("avalonnano") { return true }
        return nil
    }

    /// Original Avalon Nano 3 (cgminer 4.11.1): MODEL=nano3, PROD=Avalonnano, SWTYPE=MM318.
    /// The Nano 3s reports MM319 / nano3s and stays on the generic Canaan driver.
    public static func isAvalonNano3(versionSection: [String: JSONValue]) -> Bool {
        let joined = ["MODEL", "PROD"]
            .compactMap { versionSection[$0]?.stringValue }
            .joined(separator: " ")
        if let marker = nano3Marker(joined) { return marker }
        let swtype = (versionSection["SWTYPE"]?.stringValue ?? "").uppercased()
        return swtype.hasPrefix("MM318")
    }

    /// True when the estats `Ver[...]` names the original Nano 3 (some units omit MODEL in `version`).
    public static func estatsSaysNano3(_ stats: [String: JSONValue]) -> Bool {
        guard let section = MinerDriverParse.sectionArray(stats, key: "STATS").first,
              let text = findMMIDText(in: section),
              let ver = parseBracketedFields(text)["Ver"] else { return false }
        return nano3Marker(ver) == true
    }

    public static func fingerprint(client: CgminerClient) async -> String? {
        guard let version = try? await client.call("version") else { return nil }
        let family = fingerprint(versionResponse: version)
        guard family == "canaan" else { return family }
        if let estats = try? await client.call("estats"), estatsSaysNano3(estats) {
            return "canaannano3"
        }
        return family
    }

    // MARK: - 1. Canaan Avalon Driver

    public static func pollCanaan(client: CgminerClient, nano3: Bool = false) async throws -> MinerWatchSample {
        let version = try await client.call("version")
        let summary = (try? await client.call("summary")) ?? [:]
        let stats: [String: JSONValue]
        // `estats` is deprecated on newer Avalon firmware. `stats` carries the same MM ID block.
        if let estats = try? await client.call("estats"),
           !MinerDriverParse.sectionArray(estats, key: "STATS").isEmpty {
            stats = estats
        } else {
            stats = (try? await client.call("stats")) ?? [:]
        }
        let pools = (try? await client.call("pools")) ?? [:]
        let versionSays = MinerDriverParse.sectionArray(version, key: "VERSION").first
            .map(isAvalonNano3(versionSection:)) ?? false
        let isNano3 = nano3 || versionSays || estatsSaysNano3(stats)
        var sample = parseCanaan(
            version: version, summary: summary, stats: stats, pools: pools, host: client.host, nano3: isNano3
        )
        if isNano3, sample.workmode == nil,
           let resp = try? await client.call("ascset", parameter: "0,worklevel,get") {
            sample.workmode = parseWorklevelResponse(resp)
        }
        return sample
    }

    /// Pulls 0/1/2 out of an `ascset|0,worklevel,get` reply (`Msg=worklevel 2` or `WORKLEVEL[2]`).
    public static func parseWorklevelResponse(_ resp: [String: JSONValue]) -> Int? {
        let status = MinerDriverParse.sectionArray(resp, key: "STATUS").first
        let msg = status?["Msg"]?.stringValue ?? status?["Description"]?.stringValue
            ?? resp["_raw_text"]?.stringValue ?? ""
        if let bracketed = parseBracketedFields(msg)["WORKLEVEL"], let n = Int(bracketed), (0...2).contains(n) {
            return n
        }
        let tokens = msg.split(whereSeparator: { " ,=[]:".contains($0) })
        for token in tokens.reversed() {
            if let n = Int(token), (0...2).contains(n) { return n }
        }
        return nil
    }

    /// Avalon power-supply error bits (A10 API manual, Appendix 1). Index 0 of `PS[...]`.
    public static let powerSupplyErrorBits: [(Int, String)] = [
        (1, "Input voltage low"),
        (2, "PSU over temperature (OT1)"),
        (4, "PSU over temperature (OT2)"),
        (8, "PSU over temperature (OT3)"),
        (16, "Input over current"),
        (32, "Output voltage low"),
        (64, "Output over current"),
        (128, "Current sense error"),
        (256, "Over current (IOSA)"),
        (512, "Over current (IOSB)"),
        (1024, "Over current (IOSC)"),
        (2048, "Fan failed")
    ]

    /// Human-readable fault for a nonzero PSU error code, or nil when the code is 0.
    public static func powerSupplyFault(code: Int) -> String? {
        guard code > 0 else { return nil }
        let names = powerSupplyErrorBits.filter { code & $0.0 != 0 }.map(\.1)
        let label = names.isEmpty ? "Power supply error" : names.joined(separator: ", ")
        return "\(label) (PS error \(code))"
    }

    /// `nano3` / `Avalonnano` -> `Avalon Nano 3`. Anything else is kept.
    static func prettyNano3Model(_ model: String?) -> String {
        let raw = (model ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let blob = raw.lowercased().filter { ![" ", "-", "_"].contains($0) }
        if blob.isEmpty || ["nano3", "avalonnano", "avalonnano3"].contains(blob) { return "Avalon Nano 3" }
        if blob.hasPrefix("nano3"), !blob.contains("3s") { return "Avalon Nano 3" }
        return raw
    }

    public static func parseCanaan(
        version: [String: JSONValue],
        summary: [String: JSONValue] = [:],
        stats: [String: JSONValue] = [:],
        pools: [String: JSONValue] = [:],
        host: String = "",
        nano3: Bool = false
    ) -> MinerWatchSample {
        var sample = MinerWatchSample(family: nano3 ? "canaannano3" : "canaan", host: host, online: true)

        if let vSection = MinerDriverParse.sectionArray(version, key: "VERSION").first {
            sample.firmwareVersion = MinerDriverParse.nonEmptyString(
                vSection["LVERSION"]
                ?? vSection["CGVERSION"]
                ?? vSection["VERSION"]
                ?? vSection["CGMiner"]
            )
            sample.model = MinerDriverParse.nonEmptyString(vSection["PROD"] ?? vSection["MODEL"])
            if let mac = MinerDriverParse.nonEmptyString(vSection["MAC"]) {
                sample.mac = MinerDriverParse.formatMAC(mac)
            }
        }

        if let sSection = MinerDriverParse.sectionArray(summary, key: "SUMMARY").first {
            let mhs = MinerDriverParse.firstNonZeroFloat(
                sSection["MHS 5m"], sSection["MHS 1m"], sSection["MHS av"], sSection["MHS 5s"]
            )
            if let mhs {
                sample.hashrateTHs = MinerDriverParse.roundTo(mhs / 1_000_000.0, places: 4)
            }
            sample.accepted = MinerDriverParse.optInt(sSection["Accepted"])
            sample.rejected = MinerDriverParse.optInt(sSection["Rejected"])
            sample.bestDifficulty = MinerDriverParse.parseSIDifficulty(sSection["Best Share"])
            sample.uptimeS = MinerDriverParse.optInt(sSection["Elapsed"])
        }

        enrichCanaanFromEstats(&sample, stats: stats)
        enrichFromCgminerPools(&sample, pools: pools, assignSlots: true)
        attachCanaanPingFromEstats(&sample, stats: stats)
        if nano3 {
            sample.model = prettyNano3Model(sample.model)
        }

        if let pw = sample.powerW, let ths = sample.hashrateTHs, ths > 0 {
            sample.efficiencyWPerTHs = MinerDriverParse.roundTo(pw / ths, places: 2)
        }

        sample.raw = [
            "version": .object(version),
            "summary": .object(summary),
            "stats": .object(stats),
            "pools": .object(pools)
        ]
        return sample
    }

    private static func enrichCanaanFromEstats(_ sample: inout MinerWatchSample, stats: [String: JSONValue]) {
        guard let section = MinerDriverParse.sectionArray(stats, key: "STATS").first,
              let mmText = findMMIDText(in: section) else {
            return
        }
        let fields = parseBracketedFields(mmText)
        applyCanaanTempsAndFans(&sample, fields: fields)
        applyCanaanClocksAndPower(&sample, fields: fields)
    }

    private static func applyCanaanTempsAndFans(_ sample: inout MinerWatchSample, fields: [String: String]) {
        if let tmax = MinerDriverParse.optFloat(fields["TMax"].map(JSONValue.string)) {
            sample.tempChipC = tmax
        }
        if let tavg = MinerDriverParse.optFloat(fields["TAvg"].map(JSONValue.string)) {
            sample.tempAvgC = tavg
        }
        if let itemp = MinerDriverParse.optFloat(fields["ITemp"].map(JSONValue.string)), itemp > -200 {
            sample.tempInletC = itemp
        }
        if let otemp = MinerDriverParse.optFloat(fields["OTemp"].map(JSONValue.string)), otemp > -200 {
            sample.tempOutletC = otemp
            if sample.tempVRC == nil { sample.tempVRC = otemp }
        }

        var fans: [String: Int] = [:]
        for (k, v) in fields where k.hasPrefix("Fan") && k != "FanR" {
            if let rpm = MinerDriverParse.optInt(.string(v)) {
                fans[k.lowercased()] = rpm
            }
        }
        if !fans.isEmpty {
            sample.fansExtra = fans
            sample.fanRPM = fans.values.reduce(0, +) / fans.count
        }
        if let fanr = fields["FanR"] {
            sample.fanPct = MinerDriverParse.optFloat(.string(fanr))
        }
    }

    private static func applyCanaanClocksAndPower(_ sample: inout MinerWatchSample, fields: [String: String]) {
        if let freq = MinerDriverParse.optFloat(fields["Freq"].map(JSONValue.string)) {
            sample.frequencyMHz = freq
        }
        // `SF<n>[p1 p2 p3 p4]` are the configured PLL points per hash board (Avalon_Nano3s
        // driver-avalon.c:1490). `Freq` is a measured average, so prefer the top setpoint: it is
        // what `ascset frequency,f:f:f:f` changes and what a tuning readback must compare.
        if let setpoint = fields["SF0"].flatMap({ text in
            text.split(whereSeparator: \.isWhitespace).compactMap { Double($0) }.filter { $0 > 0 }.max()
        }) {
            sample.frequencyMHz = setpoint
        }
        let ghs = MinerDriverParse.firstNonZeroFloat(
            fields["GHSavg"].map(JSONValue.string),
            fields["GHSspd"].map(JSONValue.string)
        )
        if let ghs, sample.hashrateTHs == nil || (sample.hashrateTHs ?? 0) <= 0 {
            sample.hashrateTHs = MinerDriverParse.roundTo(ghs / 1_000.0, places: 4)
        }
        if let mpo = MinerDriverParse.optFloat(fields["MPO"].map(JSONValue.string)) {
            sample.powerW = MinerDriverParse.roundTo(mpo, places: 1)
        } else if let wall = MinerDriverParse.optFloat(fields["WALLPOWER"].map(JSONValue.string)) {
            sample.powerW = MinerDriverParse.roundTo(wall, places: 1)
        }
        applyCanaanPowerSupply(&sample, ps: fields["PS"])
        if sample.workmode == nil, fields["WORKMODE"] == nil,
           let level = MinerDriverParse.optInt(fields["WORKLEVEL"].map(JSONValue.string)) {
            sample.workmode = level
        }
        if let pvtV = fields["PVT_V0"], !pvtV.isEmpty {
            let vals = pvtV.split(whereSeparator: \.isWhitespace).compactMap {
                MinerDriverParse.optFloat(.string(String($0)))
            }
            if !vals.isEmpty {
                let avgCV = vals.reduce(0, +) / Double(vals.count)
                sample.voltageMV = Double(Int((avgCV * 10.0).rounded()))
                sample.asicCount = vals.count
            }
        }
        if sample.asicCount == nil, let ta = MinerDriverParse.optInt(fields["TA"].map(JSONValue.string)), ta > 0 {
            sample.asicCount = ta
        }
        if let wm = MinerDriverParse.optInt(fields["WORKMODE"].map(JSONValue.string)) {
            sample.workmode = wm
        }
    }

    /// `PS[err vCtrl vHash current power setV (measuredW)]`. Index 0 is the PSU error code.
    /// A10-class units report hash-board watts at index 4. Nano units put measured watts at index 6.
    private static func applyCanaanPowerSupply(_ sample: inout MinerWatchSample, ps: String?) {
        guard let ps, !ps.isEmpty else { return }
        let parts = ps.split(whereSeparator: \.isWhitespace).map { Double($0) }
        if let first = parts.first, let code = first, let fault = powerSupplyFault(code: Int(code)) {
            sample.powerFault = fault
        }
        guard sample.powerW == nil else { return }
        if parts.count > 6, let watts = parts[6], watts > 0 {
            sample.powerW = MinerDriverParse.roundTo(watts, places: 1)
        } else if parts.count == 6, let watts = parts[4], watts > 0 {
            sample.powerW = MinerDriverParse.roundTo(watts, places: 1)
        }
    }

    private static func attachCanaanPingFromEstats(_ sample: inout MinerWatchSample, stats: [String: JSONValue]) {
        guard !sample.pools.isEmpty,
              let section = MinerDriverParse.sectionArray(stats, key: "STATS").first,
              let mmText = findMMIDText(in: section) else {
            return
        }
        let fields = parseBracketedFields(mmText)
        guard let ping = MinerDriverParse.optFloat(fields["PING"].map(JSONValue.string)) else {
            return
        }
        let targetIdx = sample.pools.firstIndex(where: { $0.active == true }) ?? 0
        sample.pools[targetIdx].pingMs = ping
    }

    private static func findMMIDText(in section: [String: JSONValue]) -> String? {
        for (key, value) in section where key.hasPrefix("MM ID") {
            if let text = value.stringValue, !text.isEmpty { return text }
        }
        if let groups = section["_groups"]?.objectValue {
            for (key, value) in groups where key.hasPrefix("MM ID") {
                if let obj = value.objectValue {
                    return obj.map { "\($0.key)[\($0.value.stringValue ?? "")]" }.joined(separator: " ")
                }
            }
        }
        return nil
    }

    public static func parseBracketedFields(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        guard let regex = try? NSRegularExpression(pattern: #"([A-Za-z][A-Za-z0-9_]*)\s*\[([^\[\]]*)\]"#) else {
            return out
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, range: nsRange) {
            guard match.numberOfRanges == 3,
                  let kRange = Range(match.range(at: 1), in: text),
                  let vRange = Range(match.range(at: 2), in: text) else {
                continue
            }
            out[String(text[kRange])] = String(text[vRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return out
    }

}
