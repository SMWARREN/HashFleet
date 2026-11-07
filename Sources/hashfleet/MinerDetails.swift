import HashFleetCore
import Foundation

enum MinerDetailSection: String, CaseIterable {
    case overview = "Overview", mining = "Mining", hardware = "Hardware", pool = "Pool"
}

struct MinerTrendPoint {
    let date: Date
    let rate: Double?
}

/// Read-only presentation shared by the live miner page and `status --details`.
enum MinerDetails {
    typealias Metric = (label: String, value: String, style: String)

    static func health(_ miner: MinerStatusSnapshot, palette: DashboardPalette) -> (label: String, short: String, style: String) {
        guard miner.isOnline, let info = miner.info else { return ("Offline", "OFFLINE", palette.offline) }
        if info.raw["overheat_mode"]?.boolValue == true { return ("Overheat protection active", "OVERHEAT", palette.offline) }
        if hasFault(info, "power_fault") || hasFault(info, "hardware_fault") { return ("Miner needs attention", "FAULT", palette.offline) }
        if info.raw["miningPaused"]?.boolValue == true { return ("Mining paused", "PAUSED", palette.warning) }
        if usesBackup(info) { return ("Using backup pool", "BACKUP", palette.warning) }
        return ("Online", "ONLINE", palette.good)
    }

    static func lines(for miner: MinerStatusSnapshot, section: MinerDetailSection,
                      history: [MinerTrendPoint] = [], width: Int, palette: DashboardPalette) -> [DashboardLine] {
        var page = Page(miner: miner, history: history, width: width, palette: palette)
        guard miner.isOnline, let info = miner.info else {
            page.unavailable()
            return page.lines
        }
        page.configure(info: info)
        switch section {
        case .overview: page.overview(info)
        case .mining: page.mining(info)
        case .hardware: page.hardware(info)
        case .pool: page.pool(info)
        }
        return page.lines
    }

    /// Accumulates the lines of one detail page.
    private struct Page {
        let miner: MinerStatusSnapshot
        let history: [MinerTrendPoint]
        let width: Int
        let palette: DashboardPalette
        var lines: [DashboardLine] = []
        var diagnostics: MinerPoolDiagnostics?
        var pools: [ConfiguredMiningPool] = []
        var active: ConfiguredMiningPool?
        var accepted: Int?
        var rejected: Int?

        init(miner: MinerStatusSnapshot, history: [MinerTrendPoint], width: Int, palette: DashboardPalette) {
            self.miner = miner
            self.history = history
            self.width = width
            self.palette = palette
        }

        mutating func configure(info: MinerInfo) {
            diagnostics = MinerPoolDiagnostics(info: info)
            pools = configuredPools(info)
            active = pools.first { $0.isActive == true }
            accepted = counter(info, "sharesAccepted")
            rejected = counter(info, "sharesRejected")
        }

        var rejectedPercent: Double? {
            guard let accepted, let rejected else { return nil }
            let total = Double(accepted) + Double(rejected)
            return total > 0 ? Double(rejected) / total * 100 : nil
        }

        var efficiency: Double? {
            guard let rate = miner.hashrate, rate > 0, let power = miner.power else { return nil }
            let value = power / (rate / 1000)
            return value.isFinite ? value : nil
        }

        mutating func heading(_ text: String) {
            if !lines.isEmpty { lines.append(DashboardLine()) }
            lines.append(DashboardLine(" \(text.uppercased())", style: palette.title))
        }

        mutating func note(_ text: String, style: String? = nil) {
            lines += wrapped(text, width: max(12, width - 2)).map { DashboardLine(" \($0)", style: style ?? palette.secondary) }
        }

        mutating func metrics(_ values: [Metric]) {
            let columns = width >= 84 ? 2 : 1
            let cellWidth = (width - 2) / columns
            for start in stride(from: 0, to: values.count, by: columns) {
                var runs: [DashboardLine.Run] = [(" ", "")]
                for value in values[start..<min(start + columns, values.count)] {
                    let labelWidth = min(23, cellWidth / 2)
                    runs.append((TerminalText.fit(value.label, labelWidth), palette.secondary))
                    runs.append((TerminalText.fit(value.value, cellWidth - labelWidth),
                                 value.value == "Not reported" ? palette.secondary : value.style))
                }
                lines.append(DashboardLine(runs: runs))
            }
        }

        mutating func unavailable() {
            heading("Miner unavailable")
            note("The last check could not reach this miner. It will be checked again on the next refresh.", style: palette.offline)
            metrics([("Host", miner.address, palette.value)])
            if let error = miner.error { note(error, style: palette.warning) }
        }

        mutating func poolNotices(_ info: MinerInfo) {
            if usesBackup(info) {
                note("Using the backup pool. Check the preferred pool in the miner's settings if this was unexpected.", style: palette.warning)
            }
            if let message = diagnostics?.primaryError {
                note("Pool notice: \(message)", style: palette.warning)
                note("Reported by the miner; this may describe an earlier attempt to use its preferred pool.")
            }
        }

        func uptime() -> String {
            guard let seconds = miner.uptimeSeconds else { return "Not reported" }
            let days = seconds / 86_400, hours = (seconds % 86_400) / 3600, minutes = (seconds % 3600) / 60
            return days > 0 ? "\(days)d \(hours)h \(minutes)m" : "\(hours)h \(minutes)m"
        }

        mutating func trend() {
            guard !history.isEmpty else { return }
            heading("Recent hashrate")
            let points = Array(history.suffix(min(60, max(8, width - 4))))
            let values = points.compactMap(\.rate)
            guard points.count > 1, let low = values.min(), let high = values.max() else {
                note("A trend appears after the next refresh. It covers this CLI session only.")
                return
            }
            let bars = Array("▁▂▃▄▅▆▇█")
            let chart = points.map { point -> String in
                guard let value = point.rate else { return "·" }
                let level = high > low ? Int(((value - low) / (high - low) * 7).rounded()) : 3
                return String(bars[min(7, max(0, level))])
            }.joined()
            lines.append(DashboardLine(" \(chart)", style: palette.chart))
            let duration = max(0, Int(points.last!.date.timeIntervalSince(points.first!.date)))
            note("\(points.count) checks over \(duration)s · \(rate(low)) – \(rate(high)) · gaps mean no reading")
        }

        mutating func overview(_ info: MinerInfo) {
        let state = health(miner, palette: palette)
        heading("At a glance")
        note(state.label, style: state.style)
        if info.raw["overheat_mode"]?.boolValue == true { note("The miner reports active thermal protection. Check cooling before resuming mining.", style: palette.offline) }
        if hasFault(info, "power_fault") { note("The miner reports a power fault. Check its power supply and device status.", style: palette.offline) }
        if hasFault(info, "hardware_fault") { note("The miner reports a hardware fault. Check its device status.", style: palette.offline) }
        metrics([
            ("Hashrate", rate(miner.hashrate), palette.chart),
            ("Power", measure(miner.power, "W", 1), palette.gold),
            ("Chip temperature", measure(miner.temperature, "°C", 1), palette.value),
            ("Efficiency", measure(efficiency, "J/TH", 1), palette.gold),
            (miner.kind == .xmrig ? "Connection uptime" : "Uptime", uptime(), palette.value),
            ("Fan", measure(FleetFormat.sensor(info, keys: "fanrpm", "fanRpm"), "RPM"), palette.value)
        ])
        heading("Shares & records")
        metrics([
            ("Accepted", count(accepted), palette.good), ("Rejected", count(rejected), (rejected ?? 0) > 0 ? palette.warning : palette.value),
            ("Best ever", difficulty(info.bestDiff), palette.gold), ("Best this session", difficulty(info.bestSessionDiff), palette.chart)
        ])
        if let active {
            heading("Active pool")
            note(active.host, style: palette.value)
            if let provider = active.providerName { note(provider + (active.coin.map { " · \($0.ticker)" } ?? ""), style: palette.gold) }
        }
        poolNotices(info)
        trend()
        }

        mutating func mining(_ info: MinerInfo) {
        heading("Hashrate")
        metrics([
            ("Now", rate(miner.hashrate), palette.chart), ("1 minute", rate(FleetFormat.sensor(info, keys: "hashRate_1m")), palette.chart),
            ("10 minutes", rate(FleetFormat.sensor(info, keys: "hashRate_10m")), palette.chart),
            ("1 hour", rate(FleetFormat.sensor(info, keys: "hashRate_1h")), palette.chart),
            ("Expected", rate(FleetFormat.sensor(info, keys: "expectedHashrate")), palette.value),
            ("Efficiency", measure(efficiency, "J/TH", 1), palette.gold)
        ])
        heading("Shares")
        metrics([
            ("Accepted", count(accepted), palette.good), ("Rejected", count(rejected), (rejected ?? 0) > 0 ? palette.warning : palette.value),
            ("Pending", count(counter(info, "sharesPending")), palette.value), ("Rejected share rate", measure(rejectedPercent, "%", 2), palette.value),
            ("Best ever", difficulty(info.bestDiff), palette.gold), ("Best this session", difficulty(info.bestSessionDiff), palette.chart)
        ])
        trend()
        let domains = info.hashrateDomains
        if !domains.isEmpty {
            heading("Per-chip performance")
            for domain in domains {
                let nominal = domain.nominalHashrateGHs.map { " · nominal \(FleetFormat.number($0, decimals: 1)) GH/s" } ?? ""
                lines.append(DashboardLine(runs: [
                    (" ASIC \(domain.chipIndex + 1) domain \(domain.domainIndex + 1)  ", palette.secondary),
                    ("\(FleetFormat.number(domain.hashrateGHs, decimals: 1)) GH/s", palette.chart), (nominal, palette.secondary)
                ]))
            }
        }
        }

        mutating func hardware(_ info: MinerInfo) {
        if miner.kind == .xmrig {
            heading("XMRig")
            note("This connection does not provide cooling, voltage, or power readings.")
        } else {
            heading("Cooling & power")
            var cooling: [Metric] = [
                ("Chip temperature", measure(miner.temperature, "°C", 1), palette.value),
                ("Voltage regulator", measure(FleetFormat.sensor(info, keys: "vrTemp"), "°C", 1), palette.value),
                ("Fan speed", measure(percent(info, "fanspeed", "fanSpeed"), "%"), palette.value),
                ("Fan", measure(FleetFormat.sensor(info, keys: "fanrpm", "fanRpm"), "RPM"), palette.value),
                ("Power", measure(miner.power, "W", 1), palette.gold),
                ("Input voltage", measure(FleetFormat.sensor(info, keys: "voltage").map { $0 / 1000 }, "V", 2), palette.value)
            ]
            if info.raw["temp2"] != nil { cooling.append(("Second chip", measure(FleetFormat.sensor(info, keys: "temp2"), "°C", 1), palette.value)) }
            if info.raw["fan2rpm"] != nil || info.raw["fan2Rpm"] != nil {
                cooling.append(("Second fan", measure(FleetFormat.sensor(info, keys: "fan2rpm", "fan2Rpm"), "RPM"), palette.value))
            }
            metrics(cooling)
            heading("Clock & core voltage")
            metrics([
                ("Clock setting", measure(FleetFormat.sensor(info, keys: "frequency"), "MHz"), palette.value),
                ("Measured clock", measure(FleetFormat.sensor(info, keys: "actualFrequency"), "MHz"), palette.chart),
                ("Voltage setting", measure(FleetFormat.sensor(info, keys: "coreVoltage"), "mV"), palette.value),
                ("Measured voltage", measure(FleetFormat.sensor(info, keys: "coreVoltageActual"), "mV"), palette.chart)
            ])
        }
        heading("Device")
        metrics([
            ("ASIC", miner.asicModel ?? "Not reported", palette.value),
            ("Board", info.boardVersion.isEmpty ? "Not reported" : info.boardVersion, palette.value),
            ("Firmware", miner.firmware ?? "Not reported", palette.value),
            ("Wi-Fi signal", measure(FleetFormat.sensor(info, keys: "wifiRSSI", "wifiRssi", allowNegative: true), "dBm"), palette.value)
        ])
        }

        mutating func pool(_ info: MinerInfo) {
        heading("Pool status")
        if let active {
            note(active.host, style: palette.value)
            note("Active pool reported by the miner", style: palette.good)
            metrics([("Provider", active.providerName ?? "Not reported", palette.gold),
                     ("Coin", active.coin?.ticker ?? "Not reported", palette.gold)])
        } else {
            note("The miner has not identified its active pool.")
        }
        metrics([("Response time", measure(FleetFormat.sensor(info, keys: "responseTime"), "ms", 1), palette.chart),
                 ("Share difficulty", measure(FleetFormat.sensor(info, keys: "poolDifficulty"), "", 0), palette.value)])
        poolNotices(info)
        if !pools.isEmpty {
            heading("Configured pools")
            for pool in pools {
                let role = pool.role.replacingOccurrences(of: "fallback", with: "backup")
                    .replacingOccurrences(of: "Fallback", with: "Backup")
                note("\(pool.isActive == true ? "● " : "  ")\(role)", style: pool.isActive == true ? palette.good : palette.secondary)
                note(pool.host, style: palette.value)
            }
        }
        }
    }

    private static func usesBackup(_ info: MinerInfo) -> Bool {
        if info.raw["pools"] != nil || info.raw["activePoolIndex"] != nil {
            guard let active = configuredPools(info).first(where: { $0.isActive == true }) else { return false }
            let role = active.role.lowercased()
            return role.contains("fallback") && !role.contains("primary")
        }
        return MinerPoolDiagnostics(info: info).usingFallback == true
    }

    private static func configuredPools(_ info: MinerInfo) -> [ConfiguredMiningPool] {
        // The core's numeric accessor also accepts numeric strings. Slot identities on the
        // wire must be JSON numbers; don't turn malformed identity metadata into an active pool.
        func slot(_ value: JSONValue?) -> Bool {
            let number: Double?
            switch value {
            case .integer(let value): number = Double(value)
            case .unsignedInteger(let value): number = Double(value)
            case .number(let value): number = value
            default: number = nil
            }
            guard let number, let id = Int(exactly: number) else { return false }
            return (0...7).contains(id)
        }
        var validated = info
        for key in ["activePoolIndex", "primaryPoolIndex", "secondaryPoolIndex"] {
            if let value = info.raw[key], !slot(value) { validated.raw[key] = .null }
        }
        if let rows = info.raw["pools"]?.arrayValue,
           rows.contains(where: { !slot($0.objectValue?["id"]) }) { return [] }
        return ConfiguredMiningPool.resolve(info: validated)
    }

    private static func hasFault(_ info: MinerInfo, _ key: String) -> Bool {
        guard case .string(let text) = info.raw[key] else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func counter(_ info: MinerInfo, _ key: String) -> Int? {
        guard let value = info.raw[key]?.intValue, value >= 0 else { return nil }
        return value
    }

    private static func percent(_ info: MinerInfo, _ keys: String...) -> Double? {
        keys.compactMap { info.raw[$0]?.doubleValue }.first { $0.isFinite && (0...100).contains($0) }
    }

    private static func count(_ value: Int?) -> String { value.map { FleetFormat.number(Double($0), decimals: 0) } ?? "Not reported" }
    private static func rate(_ value: Double?) -> String { value.map { FleetFormat.hashrateWithUnit($0) } ?? "Not reported" }
    private static func measure(_ value: Double?, _ unit: String, _ decimals: Int = 0) -> String {
        guard let value, value.isFinite else { return "Not reported" }
        return FleetFormat.number(value, decimals: decimals) + (unit.isEmpty ? "" : " \(unit)")
    }
    private static func difficulty(_ value: String) -> String {
        let result = HashFleetCLI.difficulty(value)
        return result == "--" ? "Not reported" : result
    }

    private static func wrapped(_ text: String, width: Int) -> [String] {
        var lines: [String] = [], line = "", length = 0
        for character in TerminalText.safe(text) {
            let next = TerminalText.width(character)
            if length + next > width { lines.append(line); line = ""; length = 0 }
            line.append(character); length += next
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }
}
