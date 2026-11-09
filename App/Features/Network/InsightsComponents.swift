import SwiftUI
import HashFleetCore

struct InsightsSourceCard<Value: Sendable, Content: View>: View {
    let title: String
    let result: MiningDataResult<Value>
    let isDemo: Bool
    let now: Date
    @ViewBuilder var content: (Value) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FleetSectionLabel(title: title)
            if let value = result.value {
                content(value)
            } else {
                Label("Unavailable", systemImage: "exclamationmark.circle").foregroundStyle(FleetTheme.warning)
                Text(result.error?.localizedDescription ?? "No recognized data returned.")
                    .fleetFont(.callout).foregroundStyle(FleetTheme.secondary)
            }
            if isDemo {
                Text("Sample data · not live")
                    .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
            } else {
                BrowserLink(
                    label: "Source: \(result.sourceURL.host ?? "Public API")",
                    rawValue: result.sourceURL.absoluteString,
                    font: .caption,
                    alignment: .trailing
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if !isDemo {
                Text(
                    (result.error != nil || result.value == nil ? "Failed attempt · "
                        : (ChainObservation.isFresh(result, now: now) ? "" : "Stale · "))
                        + "Fetched \(result.fetchedAt.formatted(date: .abbreviated, time: .standard))"
                )
                .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
                if let date = result.sourceTimestamp {
                    Text("Source time: \(date.formatted(date: .abbreviated, time: .standard))")
                        .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fleetSectionGridCardContent()
        .fleetCard()
    }
}

/// Headline figures laid out in columns, matching the approved network board. Each column
/// keeps the same title/value pair a row would read out, so nothing is lost to VoiceOver.
struct InsightsMetricColumns: View {
    struct Metric: Identifiable {
        let title: String
        let value: String
        /// Rendered smaller beside the value so long units never push the figure onto
        /// its own wrapped line. Read back as part of the same accessibility label.
        var unit: String?
        var caption: String?
        var id: String { title }

        var spokenValue: String {
            [value, unit].compactMap { $0 }.joined(separator: " ")
        }
    }

    let metrics: [Metric]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(metrics) { InsightsRow($0.title, value: $0.spokenValue) }
            }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(metrics) { metric in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(metric.title)
                            .fleetFont(.caption)
                            .foregroundStyle(FleetTheme.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(metric.value)
                                .fleetFont(.title3, weight: .semibold, design: .rounded)
                                .monospacedDigit()
                                .foregroundStyle(FleetTheme.ink)
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                            if let unit = metric.unit {
                                Text(unit)
                                    .fleetFont(.caption2)
                                    .foregroundStyle(FleetTheme.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                            }
                        }
                        if let caption = metric.caption {
                            Text(caption)
                                .fleetFont(.caption2)
                                .foregroundStyle(FleetTheme.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Report as one static text so the pair reads exactly like the row it replaces.
                    .accessibilityRepresentation { Text("\(metric.title), \(metric.spokenValue)") }
                }
            }
        }
    }
}

struct InsightsRow: View {
    let title: String
    let value: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(_ title: String, value: String) { self.title = title; self.value = value }
    var body: some View {
        LabeledContent(title) {
            Text(value)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .fleetNumericUpdate(value, reduceMotion: reduceMotion)
        }
        .accessibilityElement(children: .combine)
    }
}

enum InsightsFormat {
    static func compact(_ value: Double) -> String {
        FleetFormat.difficulty(value)
    }
    static func hashrate(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "Not reported" }
        return FleetFormat.hashrateWithUnit(hashesPerSecond: value)
    }
    static func fee(_ value: Double?) -> String {
        value.map { FleetFormat.number($0, decimals: 2) + " sat/vB" } ?? "Not reported"
    }
    /// The same audited number as `fee`, split so the unit can be styled separately.
    static func feeRate(_ value: Double?) -> String {
        value.map { FleetFormat.number($0, decimals: 2) } ?? "Not reported"
    }
    static func feeUnit(_ value: Double?) -> String? { value == nil ? nil : "sat/vB" }
}
