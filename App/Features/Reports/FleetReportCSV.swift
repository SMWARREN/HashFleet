import Foundation

enum FleetReportCSV {
    /// Quote every cell and escape quotes, commas and line breaks. Neutralize formula-leading text
    /// even when a spreadsheet trims leading whitespace/control characters before interpreting it.
    static func cell(_ text: String) -> String {
        let ignored = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        let leading = text.unicodeScalars.first { !ignored.contains($0) }
        let formula = leading.map { "=+-@".unicodeScalars.contains($0) } ?? false
        let safe = (formula ? "'" : "") + text
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func encode(_ report: FleetReportSnapshot) -> Data {
        // One rectangular table is easier to import than mixed metadata and tabular sections.
        // A metadata-only row preserves capture time and semantics for an empty fleet.
        let headers = [
            "report_type", "captured_at_utc", "data_source", "fleet_miner_count",
            "online_last_response", "offline_last_check", "connection_unconfirmed",
            "fresh_online_count", "hashrate_subtotal_GHs", "hashrate_reporting_count",
            "power_subtotal_W", "power_reporting_count", "miner", "connection", "freshness",
            "observed_at_utc", "included_in_subtotals", "hashrate_GHs", "power_W",
            "temperature_C", "fan_RPM", "uptime_seconds", "scope", "privacy", "freshness_policy"
        ]
        let metadata = [
            "On-demand fleet snapshot", FleetReportSnapshot.timestamp(report.capturedAt),
            report.isDemo ? "Demo / simulated" : "Miner-reported",
            String(report.miners.count), String(report.onlineCount), String(report.offlineCount),
            String(report.unconfirmedCount), String(report.currentCount),
            FleetReportSnapshot.number(report.hashrate.value), String(report.hashrate.reporting),
            FleetReportSnapshot.number(report.power.value), String(report.power.reporting)
        ]
        let notes = [FleetReportSnapshot.scopeNote, FleetReportSnapshot.privacyNote, FleetReportSnapshot.freshnessNote]
        var rows = [headers]
        if report.miners.isEmpty {
            rows.append(metadata + ["No miners"] + Array(repeating: "", count: 9) + notes)
        } else {
            for miner in report.miners {
                rows.append(metadata + [
                    miner.label, miner.connection.rawValue, miner.freshness.rawValue,
                    FleetReportSnapshot.timestamp(miner.observedAt), miner.isCurrent ? "Yes" : "No",
                    FleetReportSnapshot.number(miner.hashrateGHs), FleetReportSnapshot.number(miner.powerWatts),
                    FleetReportSnapshot.number(miner.temperatureCelsius), FleetReportSnapshot.number(miner.fanRPM),
                    FleetReportSnapshot.number(miner.uptimeSeconds)
                ] + notes)
            }
        }
        return Data((rows.map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n").utf8)
    }
}
