import HashFleetCore
import Darwin
import Foundation

@MainActor
final class FleetDashboard {
    private let options: HashFleetCLI.CLIOptions
    private var devices: [MinerDevice] = []
    private var needsDiscovery = false
    private var fleet: FleetStatusSnapshot?
    private var pollTask: Task<Void, Never>?
    private var nextPoll = Date.distantPast
    private var paused = false
    private var quit = false
    private var details: Bool
    private var selectedID: UUID?
    private var sort = Sort.name
    private var input = TerminalInput()
    private var sample = 0
    private var lastFrame = ""
    private var logoExpanded = false
    private let palette = DashboardPalette()
    private var detailSection = MinerDetailSection.overview
    private var detailOffset = 0
    private var detailMaximumOffset = 0
    private var settingsEditor: MinerSettingsEditor?
    private var supportScreen: CLISupportScreen?
    private var opensSettings: Bool
    private var history: [UUID: [MinerTrendPoint]] = [:]

    private enum Sort: String, CaseIterable {
        case name, hashrate, temperature
    }

    init(options: HashFleetCLI.CLIOptions) {
        self.options = options
        details = options.details
        opensSettings = options.settings
    }

    func run() async throws {
        if !options.demo {
            if !options.addresses.isEmpty {
                devices = options.addresses.map { MinerDevice(name: $0, address: $0) }
            } else {
                switch FleetSharedStore.readDevicesState() {
                case .configured(let configured): devices = configured
                case .unconfigured: needsDiscovery = true
                case .unavailable:
                    throw DashboardError.unavailableStore
                }
            }
        }

        let terminal = try TerminalSession()
        // Dispatch handles signals outside the signal handler so terminal restoration is safe.
        let signals = [SIGINT, SIGTERM, SIGHUP]
        let previous = signals.map { signal($0, SIG_IGN) }
        let sources = signals.map { number in
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [weak self] in
                Task { @MainActor in self?.quit = true }
            }
            source.resume()
            return source
        }
        defer {
            pollTask?.cancel()
            settingsEditor?.cancel()
            terminal.restore()
            for (index, source) in sources.enumerated() {
                source.cancel()
                signal(signals[index], previous[index])
            }
        }

        while !quit && !Task.isCancelled {
            guard let bytes = terminal.input() else { break }
            handle(bytes)
            if quit { break }
            if !paused, settingsEditor == nil, supportScreen == nil, pollTask == nil, Date() >= nextPoll { refresh() }
            let size = terminal.size
            let frame = render(columns: size.columns, rows: size.rows)
            if frame != lastFrame {
                terminal.write(frame)
                lastFrame = frame
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private func refresh() {
        guard pollTask == nil else { return }
        let discovery = needsDiscovery
        pollTask = Task { [devices, options] in
            let snapshot: FleetStatusSnapshot
            if options.demo {
                snapshot = demoSnapshot()
            } else if discovery {
                let candidates = await FleetNetworkDiscovery.scanCurrent()
                snapshot = FleetStatusSnapshot(miners: candidates.map {
                    MinerStatusSnapshot(device: $0.device, info: $0.info)
                })
            } else {
                snapshot = await FleetStatusService.read(
                    devices: devices,
                    xmrigBearerToken: ProcessInfo.processInfo.environment["XMRIG_TOKEN"]
                )
            }
            guard !Task.isCancelled else { return }
            fleet = snapshot
            for miner in snapshot.miners {
                var samples = history[miner.deviceID, default: []]
                samples.append(MinerTrendPoint(date: snapshot.observedAt, rate: miner.hashrate))
                history[miner.deviceID] = Array(samples.suffix(60))
            }
            if discovery {
                self.devices = snapshot.miners.map(\.device)
                // Discovery runs once per session. Refreshes only read the discovered hosts.
                needsDiscovery = false
            }
            if selectedID == nil { selectedID = orderedMiners.first?.deviceID }
            if opensSettings, let miner = orderedMiners.first(where: { $0.deviceID == selectedID }) {
                settingsEditor = MinerSettingsEditor(miner: miner, demo: options.demo)
                opensSettings = false
            }
            nextPoll = Date().addingTimeInterval(options.interval)
            pollTask = nil
        }
    }

    private var orderedMiners: [MinerStatusSnapshot] {
        (fleet?.miners ?? []).sorted { left, right in
            switch sort {
            case .hashrate where left.hashrate != right.hashrate:
                return (left.hashrate ?? -1) > (right.hashrate ?? -1)
            case .temperature where left.temperature != right.temperature:
                return (left.temperature ?? -1) > (right.temperature ?? -1)
            default:
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
        }
    }

    private func move(_ direction: Int) {
        let miners = orderedMiners
        guard !miners.isEmpty else { return }
        let index = miners.firstIndex { $0.deviceID == selectedID } ?? 0
        selectedID = miners[min(max(index + direction, 0), miners.count - 1)].deviceID
        detailOffset = 0
    }

    private func handle(_ bytes: [UInt8]) {
        input.append(bytes)
        while let event = input.next() {
            if let supportScreen {
                let transitioned = supportScreen.handle(event)
                if supportScreen.quit { quit = true }
                if supportScreen.closed { self.supportScreen = nil }
                if transitioned { input.clear(); return }
                continue
            }
            if let editor = settingsEditor {
                if handleEditorEvent(editor, event) { return }
                continue
            }
            guard let key = navigationKey(for: event) else { continue }
            if handleKey(key) { return }
        }
    }

    /// Returns true when the remaining buffered input must be discarded.
    private func handleEditorEvent(_ editor: MinerSettingsEditor, _ event: TerminalKey) -> Bool {
        let transitioned = editor.handle(event)
        if editor.quit { quit = true }
        if editor.closed {
            editor.cancel(); settingsEditor = nil
            nextPoll = .distantPast
        }
        if transitioned { input.clear(); return true }
        return false
    }

    /// Handles arrow-style events and returns the byte of a plain key for further handling.
    private func navigationKey(for event: TerminalKey) -> UInt8? {
        switch event {
        case .up: vertical(-1); return nil
        case .down: vertical(1); return nil
        case .right: move(1); return nil
        case .left: move(-1); return nil
        case .escape: details = false; logoExpanded = false; return nil
        case .paste: return nil
        case .byte(let byte): return byte
        }
    }

    private func selectDetailSection(_ key: UInt8) {
        let sections = MinerDetailSection.allCases
        if key == 9 {
            detailSection = sections[(sections.firstIndex(of: detailSection)! + 1) % sections.count]
        } else {
            detailSection = sections[Int(key - 49)]
        }
        details = true; detailOffset = 0
    }

    /// Returns true when the remaining buffered input must be discarded.
    private func handleKey(_ key: UInt8) -> Bool {
        switch key {
        case 3, 4, 113, 81: quit = true
        case 83:
            supportScreen = CLISupportScreen()
            input.clear()
            return true
        case 106: vertical(1)
        case 107: vertical(-1)
        case 91: move(-1)
        case 93: move(1)
        case 101:
            if let miner = orderedMiners.first(where: { $0.deviceID == selectedID }) {
                settingsEditor = MinerSettingsEditor(miner: miner, demo: options.demo)
                input.clear(); return true
            }
        case 114:
            // Repeated keypresses never overlap requests, including while paused.
            refresh()
        case 32:
            paused.toggle()
            if !paused { nextPoll = .distantPast }
        case 115:
            let all = Sort.allCases
            sort = all[(all.firstIndex(of: sort)! + 1) % all.count]
        default: handleViewKey(key)
        }
        return false
    }

    private func handleViewKey(_ key: UInt8) {
        switch key {
        case 100, 13, 10: details.toggle(); detailOffset = 0
        case 49...52, 9: selectDetailSection(key)
        case 98: details = false; logoExpanded = false
        case 108, 76: logoExpanded.toggle()
        default: break
        }
    }

    private func vertical(_ direction: Int) {
        if details { detailOffset = min(detailMaximumOffset, max(0, detailOffset + direction)) } else { move(direction) }
    }

    private func render(columns: Int, rows: Int) -> String {
        // Leave the last terminal column unused to avoid automatic line wrapping.
        let width = min(max(columns - 1, 1), 124)
        let height = max(rows, 1)
        if let supportScreen { return supportScreen.render(width: width, height: height, palette: palette) }
        if let settingsEditor { return settingsEditor.render(width: width, height: height, palette: palette) }
        if logoExpanded {
            return "\u{1B}[H" + DashboardBrand.preview(width: width, height: height, palette: palette)
                .prefix(height).map { $0.render(width: width) }.joined(separator: "\r\n") + "\u{1B}[J"
        }
        if details, width >= 44, height >= 12,
           let miner = orderedMiners.first(where: { $0.deviceID == selectedID }) {
            return renderDetails(miner, width: width, height: height)
        }
        let lines = width < 44 || height < 12
            ? renderTooSmall()
            : renderFleet(width: width, height: height)
        return "\u{1B}[H" + lines.prefix(height).map { $0.render(width: width) }.joined(separator: "\r\n") + "\u{1B}[J"
    }

    private func renderTooSmall() -> [DashboardLine] {
        [
            DashboardLine("HASH FLEET", style: palette.title),
            DashboardLine("Resize to at least 45 columns × 12 rows.", style: ""),
            DashboardLine("q quit · Ctrl+C quit", style: palette.secondary)
        ]
    }

    private func statusText() -> String {
        if pollTask != nil {
            return needsDiscovery ? "Finding miners on the local network…" : "Refreshing miner readings…"
        } else if paused {
            return "PAUSED · readings are frozen"
        } else if let fleet {
            let age = max(0, Int(Date().timeIntervalSince(fleet.observedAt)))
            return "Updated \(age)s ago · next refresh in \(max(0, Int(ceil(nextPoll.timeIntervalSinceNow))))s"
        }
        return "Connecting to your fleet…"
    }

    private func renderFleet(width: Int, height: Int) -> [DashboardLine] {
        let dim = palette.secondary
        let mode = options.demo ? "DEMO · SAMPLE DATA" : "LIVE · FLEET STATUS"
        var lines = DashboardBrand.header(
            width: width, height: height,
            content: DashboardBrand.HeaderContent(mode: mode, state: statusText(), paused: paused),
            palette: palette
        )
        lines.append(DashboardLine(String(repeating: "─", count: width), style: dim))

        if let fleet {
            lines += fleetListLines(fleet, width: width, height: height, used: lines.count)
        } else {
            lines.append(DashboardLine(" Waiting for the first snapshot…", style: dim))
            lines.append(DashboardLine(" You can quit while requests are in progress.", style: dim))
        }
        // Anchor controls to the bottom of the viewport.
        if lines.count > height - 2 { lines = Array(lines.prefix(height - 2)) }
        while lines.count < height - 2 { lines.append(DashboardLine()) }
        lines.append(DashboardLine(String(repeating: "─", count: width), style: dim))
        lines.append(DashboardLine(width >= 110 ? " ↑↓/jk select · d details · e settings · r refresh · space pause · s sort · S support · l logo · q quit"
            : width >= 70 ? " j/k select · d details · e settings · S support · q quit"
            : width >= 60 ? " j/k select · d details · e edit · S support · q quit"
            : " j/k · d info · e edit · S support · q quit", style: dim))
        return lines
    }

    private func fleetTotalsLines(_ fleet: FleetStatusSnapshot, width: Int) -> [DashboardLine] {
        let gold = palette.title
        let dim = palette.secondary
        var lines: [DashboardLine] = []
        func add(_ text: String, _ style: String) { lines.append(DashboardLine(text, style: style)) }
        let rates = fleet.miners.compactMap(\.hashrate)
        let powers = fleet.miners.compactMap(\.powerWatts)
        let rate = rates.isEmpty ? "--" : FleetFormat.hashrateWithUnit(rates.reduce(0, +))
        let power = powers.isEmpty ? "--" : FleetFormat.number(powers.reduce(0, +), decimals: 1) + " W"
        let online = "ONLINE  \(fleet.onlineCount)/\(fleet.miners.count)"
        if width >= 76 {
            add(" " + TerminalText.fit("HASHRATE  \(rate)", 28) + TerminalText.fit("POWER  \(power)", 25) + online, gold)
        } else {
            add(" HASHRATE  \(rate)    \(online)", gold)
            add(" POWER     \(power)", gold)
        }
        if !fleet.miners.isEmpty && (rates.count < fleet.miners.count || powers.count < fleet.miners.count) {
            add(" Subtotals · hashrate \(rates.count)/\(fleet.miners.count) reported"
                + " · power \(powers.count)/\(fleet.miners.count) reported", palette.warning)
        } else {
            let health = fleet.miners.isEmpty ? "No miners available"
                : fleet.offlineCount == 0 ? "All miners responding" : "\(fleet.offlineCount) offline"
            add(" \(health) · sort: \(sort.rawValue)",
                fleet.onlineCount > 0 && fleet.offlineCount == 0 ? palette.good : palette.warning)
        }
        if width >= 76 { add(String(repeating: "─", count: width), dim) }
        return lines
    }

    private func fleetListLines(_ fleet: FleetStatusSnapshot, width: Int, height: Int, used: Int) -> [DashboardLine] {
        let dim = palette.secondary
        var lines = fleetTotalsLines(fleet, width: width)
        if width < 76 && height > 12 { lines.append(DashboardLine(String(repeating: "─", count: width), style: dim)) }

        let miners = orderedMiners
        let compact = width < 76
        let wide = width >= 108
        let rowHeight = compact ? 3 : 2
        // Keep the pager and keyboard controls visible even in shallow split panes.
        if !compact {
            lines.append(DashboardLine("   " + TerminalText.fit("MINER", 23) + TerminalText.fit("STATE", 9)
                + TerminalText.fit("HASHRATE", 13, right: true)
                + TerminalText.fit("TEMP", 11, right: true)
                + TerminalText.fit("POWER", 12, right: true)
                + (wide ? TerminalText.fit("BEST (ALL)", 15, right: true)
                    + TerminalText.fit("BEST (SESSION)", 17, right: true) : ""), style: dim))
        }
        let count = max(1, (height - (used + lines.count) - 3) / rowHeight)
        let selection = miners.firstIndex { $0.deviceID == selectedID } ?? 0
        let first = (selection / count) * count
        let end = min(first + count, miners.count)
        if miners.isEmpty {
            lines.append(DashboardLine(" No miners to display.", style: palette.warning))
            lines.append(DashboardLine(" Run: hashfleet watch <miner-host>", style: dim))
        } else {
            for miner in miners[first..<end] {
                lines += minerRowLines(miner, compact: compact, wide: wide)
            }
        }
        let pager = miners.isEmpty ? "0 miners" : "\(first + 1)–\(end) of \(miners.count) miners"
        lines.append(DashboardLine(" \(pager) · sort: \(sort.rawValue)", style: dim))
        return lines
    }

    private func minerRowLines(_ miner: MinerStatusSnapshot, compact: Bool, wide: Bool) -> [DashboardLine] {
        var lines: [DashboardLine] = []
        let active = miner.deviceID == selectedID
        let rate = miner.hashrate.map { FleetFormat.hashrateWithUnit($0) } ?? "--"
        let temp = miner.temperature.map { FleetFormat.number($0, decimals: 1) + " °C" } ?? "--"
        let power = miner.power.map { FleetFormat.number($0, decimals: 1) + " W" } ?? "--"
        let health = MinerDetails.health(miner, palette: palette)
        let status = health.short
        let marker = active ? " › " : "   "
        let statusColor = health.style
        if compact {
            if active {
                lines.append(DashboardLine("\(marker)\(miner.name) · \(status)", style: palette.selection))
            } else {
                lines.append(DashboardLine(runs: [("\(marker)\(miner.name) · ", ""), (status, statusColor)]))
            }
            lines.append(DashboardLine("   \(rate)  ·  \(temp)  ·  \(power)", style: ""))
        } else {
            let identity = marker + TerminalText.fit(miner.name, 23)
            let state = TerminalText.fit(status, 9)
            let metrics = TerminalText.fit(rate, 13, right: true) + TerminalText.fit(temp, 11, right: true)
                + TerminalText.fit(power, 12, right: true)
                + (wide ? TerminalText.fit(HashFleetCLI.difficulty(miner.info?.bestDiff), 15, right: true)
                    + TerminalText.fit(HashFleetCLI.difficulty(miner.info?.bestSessionDiff), 17, right: true) : "")
            if active {
                lines.append(DashboardLine(identity + state + metrics, style: palette.selection))
            } else {
                lines.append(DashboardLine(runs: [(identity, ""), (state, statusColor), (metrics, "")]))
            }
        }
        lines.append(DashboardLine("   \(miner.address)\(miner.error.map { " · " + $0 } ?? "")",
            style: miner.isOnline ? palette.secondary : palette.offline))
        return lines
    }

    private func renderDetails(_ miner: MinerStatusSnapshot, width: Int, height: Int) -> String {
        let health = MinerDetails.health(miner, palette: palette)
        var lines = [DashboardLine(" HASH FLEET / DETAILS / \(miner.name)", style: palette.title)]
        let age = max(0, Int(Date().timeIntervalSince(miner.observedAt)))
        let freshness = paused ? "Paused · readings frozen" : pollTask != nil ? "Refreshing…" : "Updated \(age)s ago"
        lines.append(DashboardLine(runs: [(" \(health.label)", health.style), ("  ·  \(freshness)", palette.secondary)]))
        lines.append(DashboardLine(" \(miner.address)\(options.demo ? " · DEMO · SAMPLE DATA" : "")", style: palette.secondary))
        var tabs: [DashboardLine.Run] = []
        for (index, section) in MinerDetailSection.allCases.enumerated() {
            tabs.append((" \(index + 1) \(section.rawValue) ", section == detailSection ? palette.selection : palette.secondary))
        }
        lines.append(DashboardLine(runs: tabs))
        lines.append(DashboardLine(String(repeating: "─", count: width), style: palette.secondary))
        let body = MinerDetails.lines(for: miner, section: detailSection, history: history[miner.deviceID, default: []], width: width, palette: palette)
        let available = max(1, height - lines.count - 3)
        detailMaximumOffset = max(0, body.count - available)
        detailOffset = min(detailOffset, detailMaximumOffset)
        lines += body.dropFirst(detailOffset).prefix(available)
        while lines.count < height - 3 { lines.append(DashboardLine()) }
        let page = detailMaximumOffset > 0 ? " · lines \(detailOffset + 1)–\(min(body.count, detailOffset + available))/\(body.count)" : ""
        lines.append(DashboardLine(" \(detailSection.rawValue)\(page) · ←/→ change miner", style: palette.secondary))
        lines.append(DashboardLine(String(repeating: "─", count: width), style: palette.secondary))
        lines.append(DashboardLine(width >= 110
            ? " 1–4/Tab section · ↑↓/jk scroll · e settings · S support · d/Esc fleet · r refresh · q quit"
            : width >= 70 ? " 1–4/Tab · jk scroll · e edit · S support · d/Esc back · q quit"
            : " 1–4 jk · e · S support · d back · q quit", style: palette.secondary))
        return "\u{1B}[H" + lines.map { $0.render(width: width) }.joined(separator: "\r\n") + "\u{1B}[J"
    }

    private func demoSnapshot() -> FleetStatusSnapshot {
        sample += 1
        let names = ["Gamma / desk", "Gamma / studio", "Naja Duo / rack", "Naja Duo / spare"]
        let rates = [1_420.0, 1_210, 10_090, 0]
        let miners = names.enumerated().map { index, name in
            let device = MinerDevice(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)")!,
                name: name, address: "miner-\(index + 1).example"
            )
            guard index != 3 else { return MinerStatusSnapshot(device: device, error: "Sample offline miner") }
            let info = MinerInfo(raw: [
                "hashRate": .number(rates[index] * (1 + sin(Double(sample + index)) * 0.015)),
                "temp": .number([59.5, 51.4, 46.0][index]),
                "power": .number([20.1, 17.6, 127.1][index]),
                "bestDiff": .string(["1.32G", "51.62G", "14.47G"][index]),
                "bestSessionDiff": .string(["200M", "120M", "87M"][index]),
                "ASICModel": .string("BM1370"), "version": .string("demo"),
                "uptimeSeconds": .integer(86_400), "isUsingFallbackStratum": .integer(0),
                "hashRate_1m": .number(rates[index] * 0.98), "hashRate_10m": .number(rates[index] * 0.97),
                "hashRate_1h": .number(rates[index] * 0.99), "expectedHashrate": .number(rates[index]),
                "sharesAccepted": .integer(Int64(12500 + index * 3000)), "sharesRejected": .integer(Int64(index + 1)),
                "sharesPending": .integer(0), "fanspeed": .integer(65), "fanrpm": .integer(4200),
                "vrTemp": .number(47.2), "voltage": .integer(5120), "frequency": .integer(575),
                "actualFrequency": .number(574.8), "coreVoltage": .integer(1200), "coreVoltageActual": .integer(1194),
                "wifiRSSI": .integer(-57), "boardVersion": .string("Demo board"),
                "stratumURL": .string("solo.ckpool.org"), "responseTime": .number(32.4), "poolDifficulty": .integer(1024)
            ])
            return MinerStatusSnapshot(device: device, info: info)
        }
        return FleetStatusSnapshot(miners: miners)
    }

    private enum DashboardError: LocalizedError {
        case unavailableStore
        var errorDescription: String? {
            "The configured fleet store is unavailable or corrupt; refusing local discovery. Pass explicit miner hosts to continue."
        }
    }
}
