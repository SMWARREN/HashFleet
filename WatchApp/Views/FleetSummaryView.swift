import HashFleetWatchCore
import SwiftUI

/// Fleet totals. Counts only fresh readings and says so when the total is partial.
struct FleetSummaryView: View {
    let store: WatchFleetStore

    var body: some View {
        // Re-evaluates on a timer so freshness changes without any network work.
        TimelineView(.periodic(from: .now, by: 5)) { context in
            SummaryContent(store: store, now: context.date)
        }
    }
}

private struct SummaryContent: View {
    let store: WatchFleetStore
    let now: Date

    var body: some View {
        let totals = FleetTotals(store: store, now: now)
        VStack(alignment: .leading, spacing: 4) {
            Text(hashrateText(totals))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.hashGold)
                .lineLimit(2)
            Text("\(totals.currentCount) of \(totals.minerCount) current")
                .font(.footnote)
            Text(powerText(totals))
                .font(.footnote)
            if !store.isDemo, let observedAt = oldestObservation {
                Text("Updated \(observedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if let note = partialNote(totals) {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(totals))
        .accessibilityValue(oldestObservation.map { String($0.timeIntervalSince1970) } ?? "No readings")
        .accessibilityIdentifier("watch.summary")
        .privacySensitive()
    }

    /// The oldest saved observation advances only after every displayed miner has received a newer reading.
    private var oldestObservation: Date? {
        store.miners.compactMap { store.readings[$0.id]?.observedAt }.min()
    }

    /// A subtotal is always labelled with how many current miners reported it.
    private func hashrateText(_ totals: FleetTotals) -> String {
        guard totals.hashrateReporters > 0 else { return "Hashrate: \(WatchFormat.notReported)" }
        let value = WatchFormat.hashrate(totals.hashrateGHs)
        return totals.isHashratePartial || totals.isPartialFleet
            ? "\(value) from \(totals.hashrateReporters) of \(totals.minerCount)"
            : value
    }

    private func powerText(_ totals: FleetTotals) -> String {
        guard totals.powerReporters > 0 else { return "Power: \(WatchFormat.notReported)" }
        let value = WatchFormat.power(totals.powerWatts)
        return totals.isPowerPartial || totals.isPartialFleet
            ? "\(value) from \(totals.powerReporters) of \(totals.minerCount)"
            : value
    }

    private func partialNote(_ totals: FleetTotals) -> String? {
        var gaps: [String] = []
        if totals.isPartialFleet { gaps.append("Only fresh readings are counted.") }
        if totals.isHashratePartial { gaps.append("Some current miners didn't report hashrate.") }
        if totals.isPowerPartial { gaps.append("Some current miners didn't report power.") }
        return gaps.isEmpty ? nil : "Partial total. " + gaps.joined(separator: " ")
    }

    private func accessibilityLabel(_ totals: FleetTotals) -> String {
        var parts = ["Fleet summary", hashrateText(totals), powerText(totals)]
        parts.insert("\(totals.currentCount) of \(totals.minerCount) miners current", at: 1)
        if let note = partialNote(totals) { parts.append(note) }
        return parts.joined(separator: ", ")
    }
}
