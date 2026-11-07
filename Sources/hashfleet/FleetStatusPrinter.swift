import HashFleetCore
import Darwin
import Foundation

/// A styled snapshot in normal terminal scrollback; never takes over keyboard or screen state.
enum FleetStatusPrinter {
    static func print(_ fleet: FleetStatusSnapshot, searchedLocally: Bool, details: Bool) {
        setlocale(LC_CTYPE, "")
        let width = max(1, min(124, TerminalSession.outputSize.columns - 1))
        let palette = DashboardPalette()
        func write(_ line: DashboardLine) { Swift.print(line.render(width: width, fillRow: false)) }
        func text(_ value: String = "", _ style: String = "") { write(DashboardLine(value, style: style)) }
        func divider() { text(String(repeating: "─", count: width), palette.secondary) }
        for line in DashboardBrand.statusHeader(width: width,
            state: "\(fleet.onlineCount)/\(fleet.miners.count) online", palette: palette) {
            write(line)
        }
        divider()
        guard !fleet.miners.isEmpty else {
            text(searchedLocally ? " No miners found on the local network." : " No miners configured.", palette.warning)
            text(" Run: hashfleet status <miner-host>", palette.secondary)
            return
        }

        let compact = width < 76
        let wide = width >= 108
        if !compact {
            text(" " + TerminalText.fit("MINER", 23) + TerminalText.fit("STATE", 10)
                + TerminalText.fit("HASHRATE", 13, right: true)
                + TerminalText.fit("TEMP", 11, right: true)
                + TerminalText.fit("POWER", 12, right: true)
                + (wide ? TerminalText.fit("BEST (ALL)", 14, right: true)
                    + TerminalText.fit("BEST (SESSION)", 17, right: true) : ""), palette.gold)
        }
        for (index, miner) in fleet.miners.enumerated() {
            if index > 0 { text() }
            let health = MinerDetails.health(miner, palette: palette)
            let rate = miner.hashrate.map { FleetFormat.hashrateWithUnit($0) } ?? "--"
            let temp = miner.temperatureCelsius.map { FleetFormat.number($0, decimals: 1) + " °C" } ?? "--"
            let power = miner.powerWatts.map { FleetFormat.number($0, decimals: 1) + " W" } ?? "--"
            let allTime = HashFleetCLI.difficulty(miner.info?.bestDiff)
            let session = HashFleetCLI.difficulty(miner.info?.bestSessionDiff)
            func value(_ text: String, _ columns: Int, _ style: String) -> DashboardLine.Run {
                (TerminalText.fit(text, columns, right: true), text == "--" ? palette.secondary : style)
            }
            if compact {
                write(DashboardLine(runs: [
                    (" " + TerminalText.fit(miner.name, max(1, width - health.short.count - 4)), palette.value),
                    (" · ", palette.secondary), (health.short, health.style)
                ]))
            } else {
                var runs: [DashboardLine.Run] = [
                    (" " + TerminalText.fit(miner.name, 23), palette.value),
                    (TerminalText.fit(health.short, 10), health.style),
                    value(rate, 13, palette.chart), value(temp, 11, palette.value), value(power, 12, palette.gold)
                ]
                if wide { runs += [value(allTime, 14, palette.gold), value(session, 17, palette.chart)] }
                write(DashboardLine(runs: runs))
            }
            text(" \(miner.address)", palette.secondary)
            printSecondaryRows(
                values: SecondaryValues(rate: rate, temp: temp, power: power, allTime: allTime, session: session),
                layout: (width: width, compact: compact, wide: wide), palette: palette, write: write
            )
            if let error = miner.error { text(" \(error)", palette.offline) }
            if details, miner.isOnline {
                text()
                for section in MinerDetailSection.allCases {
                    for line in MinerDetails.lines(for: miner, section: section, width: width, palette: palette) { write(line) }
                }
            }
        }
        divider()
    }

    private struct SecondaryValues {
        let rate: String
        let temp: String
        let power: String
        let allTime: String
        let session: String
    }

    private static func printSecondaryRows(
        values: SecondaryValues,
        layout: (width: Int, compact: Bool, wide: Bool), palette: DashboardPalette,
        write: (DashboardLine) -> Void
    ) {
        let (rate, temp, power) = (values.rate, values.temp, values.power)
        let (allTime, session) = (values.allTime, values.session)
        let width = layout.width
        if layout.compact {
            if width >= 48 {
                write(DashboardLine(runs: [(" ", ""), (rate, palette.chart), ("  ·  ", palette.secondary),
                    (temp, palette.value), ("  ·  ", palette.secondary), (power, palette.gold)]))
            } else {
                for (label, value, style) in [("Hashrate", rate, palette.chart),
                                             ("Temp", temp, palette.value), ("Power", power, palette.gold)] {
                    write(DashboardLine(runs: [(" \(label)  ", palette.secondary), (value, style)]))
                }
            }
        }
        if !layout.wide {
            let records: [DashboardLine.Run] = [(" Best ever  ", palette.secondary), (allTime, palette.gold)]
            let current: [DashboardLine.Run] = [(" Best this session  ", palette.secondary), (session, palette.chart)]
            if width >= 60 {
                write(DashboardLine(runs: records + [("   ", "")] + current))
            } else {
                write(DashboardLine(runs: records))
                write(DashboardLine(runs: current))
            }
        }
    }
}
