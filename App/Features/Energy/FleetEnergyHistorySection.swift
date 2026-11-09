import SwiftUI
import Charts
import HashFleetCore

/// Stat card adapted from ShipSwift's `SWKPICard`: tinted icon and title, a bold value, and a
/// trailing change tag. Static, with no idle animation.
struct FleetEnergyStatCard: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color
    /// Signed percent change, nil hides the tag in favor of `note`.
    let change: Double?
    let comparison: String
    var note: String?
    /// Energy and cost going up is bad, so up is drawn in the warning color.
    var increaseIsBad = true
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(title)
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(value)
                .fleetFont(.title3, weight: .bold, design: .rounded)
                .foregroundStyle(FleetTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let change {
                FleetEnergyChangeTag(change: change, comparison: comparison, increaseIsBad: increaseIsBad)
            } else if let note {
                Text(note)
                    .fleetFont(.caption2)
                    .foregroundStyle(FleetTheme.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FleetTheme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(tint.opacity(0.18), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// Delta tag adapted from ShipSwift's `SWKPIDeltaTag`.
struct FleetEnergyChangeTag: View {
    let change: Double
    let comparison: String
    let increaseIsBad: Bool

    static func text(_ change: Double) -> String {
        let rounded = (abs(change) * 10).rounded() / 10
        if rounded == 0 { return "0%" }
        return (change > 0 ? "+" : "−") + rounded.formatted(.number.precision(.fractionLength(0...1))) + "%"
    }

    private var tint: Color {
        let rounded = (abs(change) * 10).rounded() / 10
        if rounded == 0 { return FleetTheme.secondary }
        return (change > 0) == increaseIsBad ? FleetTheme.warning : FleetTheme.positive
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: change > 0 ? "arrow.up.right" : (change < 0 ? "arrow.down.right" : "equal"))
                .font(.system(size: 9, weight: .bold))
            Text(Self.text(change))
                .font(FleetTheme.mono(10).weight(.semibold))
            Text(comparison)
                .fleetFont(.caption2)
                .foregroundStyle(FleetTheme.secondary)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
    }
}

/// "Measured use" section: what the miners actually drew, from readings saved on this device.
/// Loads once on appear and again every few minutes, not every second.
struct FleetEnergyHistorySection: View {
    let store: FleetStore
    let rate: Double?
    let currency: String

    @State private var days: [FleetDailyEnergy] = []
    @State private var loaded = false

    private static let refreshInterval: Duration = .seconds(300)

    private var yesterday: FleetDailyEnergy? { days.dropLast().last }
    private var dayBefore: FleetDailyEnergy? { days.dropLast(2).last }
    private var previousSix: [FleetDailyEnergy] { Array(days.dropLast().suffix(6)) }

    var body: some View {
        FleetSettingsSection(content: {
            FleetSettingsRow {
                cards
            }
            FleetSettingsRow(showsSeparator: false) {
                chart
            }
        }, header: {
            Text("Measured use")
        }, footer: {
            Text("Measured from power readings saved on this device while Hash Fleet was running. "
                + "Hours with no readings are left out, so days marked partial read low. "
                + "Changes compare only fully covered days. Not a utility meter or bill.")
                .accessibilityIdentifier("energy.history.footer")
        })
        .fleetSettingsSectionIdentifier("energy.historySection")
        .task(id: store.visibleDevices.map(\.id)) { await refreshLoop() }
    }

    private var cards: some View {
        let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]
        let yesterdayKWh = yesterday.flatMap { $0.isWellCovered ? $0.kWh : nil }
        let dayBeforeKWh = dayBefore.flatMap { $0.isWellCovered ? $0.kWh : nil }
        let covered = previousSix.filter(\.isWellCovered)
        let weekAverageWatts = covered.isEmpty ? nil : covered.compactMap(\.averageWatts).reduce(0, +) / Double(covered.count)
        let liveWatts = FleetEnergyEstimate.capture(store: store).watts
        return LazyVGrid(columns: columns, spacing: 10) {
            FleetEnergyStatCard(
                title: "Yesterday",
                value: yesterdayKWh.map { Self.kWh($0) }
                    ?? (yesterday.flatMap { $0.coveredMinerMinutes > 0 ? Self.kWh($0.kWh) + " partial" : nil } ?? "—"),
                symbol: "bolt.fill",
                tint: FleetSidebarTileTint.yellow.color,
                change: FleetEnergyComparison.percentChange(current: yesterdayKWh, baseline: dayBeforeKWh),
                comparison: "vs day before",
                note: yesterdayKWh == nil ? "Not enough readings for a full day yet" : "Day before not fully covered",
                identifier: "energy.history.yesterday"
            )
            FleetEnergyStatCard(
                title: "Yesterday's cost",
                value: costText(yesterdayKWh),
                symbol: "dollarsign.circle.fill",
                tint: FleetSidebarTileTint.green.color,
                change: rate == nil ? nil
                    : FleetEnergyComparison.percentChange(current: yesterdayKWh, baseline: dayBeforeKWh),
                comparison: "vs day before",
                note: rate == nil ? "Set your rate above" : "Needs two full days",
                identifier: "energy.history.yesterdayCost"
            )
            FleetEnergyStatCard(
                title: "Power now",
                value: liveWatts.map { Self.watts($0) } ?? "—",
                symbol: "gauge.with.dots.needle.67percent",
                tint: FleetSidebarTileTint.orange.color,
                change: FleetEnergyComparison.percentChange(current: liveWatts, baseline: weekAverageWatts),
                comparison: "vs 7-day avg",
                note: "Needs a full day of readings",
                identifier: "energy.history.powerNow"
            )
            FleetEnergyStatCard(
                title: "Efficiency",
                value: store.efficiencyReading.value.map {
                    $0.formatted(.number.precision(.fractionLength(1))) + " J/TH"
                } ?? "—",
                symbol: "leaf.fill",
                tint: FleetSidebarTileTint.teal.color,
                change: nil,
                comparison: "",
                note: store.efficiencyReading.hasReading ? "Lower is better" : "Needs power and hashrate from every online miner",
                identifier: "energy.history.efficiency"
            )
        }
    }

    @ViewBuilder
    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LAST 7 DAYS")
                    .fleetFont(.caption2, weight: .semibold, design: .monospaced)
                    .foregroundStyle(FleetTheme.secondary)
                Spacer()
                let total = days.map(\.kWh).reduce(0, +)
                if total > 0 {
                    Text(Self.kWh(total) + " measured")
                        .fleetFont(.caption2)
                        .foregroundStyle(FleetTheme.secondary)
                }
            }
            if !loaded {
                ProgressView().frame(maxWidth: .infinity, minHeight: 140)
            } else if days.allSatisfy({ $0.coveredMinerMinutes == 0 }) {
                Text("No saved power readings yet. Bars appear as Hash Fleet records your miners.")
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            } else {
                Chart(days) { day in
                    BarMark(
                        x: .value("Day", day.day, unit: .day),
                        y: .value("kWh", day.kWh)
                    )
                    .foregroundStyle(FleetSidebarTileTint.yellow.color.opacity(day.isWellCovered ? 1 : 0.4))
                    .cornerRadius(4)
                    .annotation(position: .top, spacing: 2) {
                        if !day.isWellCovered, day.coveredMinerMinutes > 0 {
                            Text(day.isToday ? "so far" : "partial")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(FleetTheme.secondary)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(FleetTheme.separator)
                        AxisValueLabel {
                            if let kWh = value.as(Double.self) { Text(kWh.formatted(.number.precision(.fractionLength(0...1)))) }
                        }
                    }
                }
                .chartYAxisLabel("kWh")
                .frame(height: 160)
                .accessibilityLabel("Measured energy per day for the last 7 days")
                .accessibilityValue(days.map { day in
                    "\(day.day.formatted(.dateTime.weekday(.wide))): \(Self.kWh(day.kWh))"
                        + (day.isWellCovered ? "" : (day.isToday ? " so far" : ", partial"))
                }.joined(separator: "; "))
                .accessibilityIdentifier("energy.history.chart")
            }
        }
    }

    private func costText(_ kWh: Double?) -> String {
        guard let rate else { return "—" }
        guard let kWh else { return "—" }
        let cost = kWh * rate
        return cost.isFinite ? cost.formatted(.currency(code: currency)) : "—"
    }

    private func refreshLoop() async {
        while !Task.isCancelled {
            await load()
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }

    private func load() async {
        let devices = store.visibleDevices
        guard !store.isDemo else {
            days = FleetDailyEnergyBuilder.build(minutes: [], minerCount: devices.count)
            loaded = true
            return
        }
        let calendar = Calendar.current
        let now = Date.now
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        await MinerTelemetryDatabase.shared.flushReadings()
        let minutes = await MinerTelemetryDatabase.shared.getPowerMinutes(
            minerIds: devices.map(\.id.uuidString), since: start, until: now
        )
        days = FleetDailyEnergyBuilder.build(minutes: minutes, minerCount: devices.count, now: now, calendar: calendar)
        loaded = true
    }

    static func kWh(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(value < 10 ? 2 : 1)))) kWh"
    }

    static func watts(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0)))) W"
    }
}
