import SwiftUI
import HashFleetCore

struct SoloOutcomeScope: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let hashrateHPS: Double
}

enum SoloOutcomeWindow: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year

    var id: Self { self }

    var duration: TimeInterval {
        switch self {
        case .day: 86400
        case .week: 7 * 86400
        case .month: 30 * 86400
        case .year: 365.25 * 86400
        }
    }

    var title: String {
        switch self {
        case .day: "1 day"
        case .week: "7 days"
        case .month: "30 days"
        case .year: "1 year"
        }
    }

    var accessibilityTitle: String { "Chance over \(title)" }
}

extension NetworkInsightsView {
    func soloCard(_ network: NetworkSnapshot, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            FleetSectionLabel(title: "Solo mining · outcomes by hashrate")
            if ChainObservation.isFresh(network.mining, now: now),
                let difficulty = network.mining.value?.difficulty {
                let scopes = soloOutcomeScopes(now: now)
                if scopes.isEmpty {
                    Text("Needs a current hashrate reading from at least one online miner.")
                        .foregroundStyle(FleetTheme.secondary)
                } else {
#if os(macOS)
                    Text("Bitcoin block odds shown for the selected reported hashrate. Choose the whole fleet or an individual miner to compare.")
                        .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
#else
                    Text(
                        "Bitcoin block odds shown for the selected reported hashrate. "
                            + "Swipe to compare the whole fleet with each miner."
                    )
                    .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
#endif
#if os(macOS)
                    MacSoloOutcomeSelector(scopes: scopes) { scope in
                        AnyView(soloOutcomePage(scope: scope, difficulty: difficulty))
                    }
#else
                    VStack(spacing: 0) {
                        TabView {
                            ForEach(scopes) { scope in
                                soloOutcomePage(scope: scope, difficulty: difficulty)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .automatic))
                    }
                    .frame(minHeight: 238, maxHeight: 280)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("insights.soloOutcomePager")
#endif
                }
                Text(
                    "Uses unchanged difficulty and continuous mining. "
                        + "These are probability estimates, not countdowns, earnings forecasts or guarantees. "
                        + "Offline miners and past shares are excluded."
                )
                .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
            } else {
                Text("Needs a current hashrate reading and network difficulty fetched within the last five minutes.")
                    .foregroundStyle(FleetTheme.secondary)
            }
        }
        .fleetSectionGridCardContent()
        .fleetCard()
        .accessibilityIdentifier("insights.solo")
    }

    func soloOutcomeScopes(now: Date) -> [SoloOutcomeScope] {
        var scopes: [SoloOutcomeScope] = []
        let fleetRate = fleet.hashrateReading
        if fleetRate.hasReading, fleetRate.isComplete {
            scopes.append(
                SoloOutcomeScope(
                    id: "fleet",
                    title: "Whole online fleet",
                    subtitle: "All complete online readings",
                    hashrateHPS: fleetRate.value * 1e9
                )
            )
        }
        for device in fleet.devices {
            guard let snapshot = fleet.snapshots[device.id], snapshot.error == nil,
                let info = snapshot.info, let updatedAt = snapshot.updatedAt,
                fleet.isDemo || now.timeIntervalSince(updatedAt) <= FleetGlance.freshnessInterval * 3,
                let hashrate = FleetFormat.sensor(info, keys: "hashRate", "hashrate"), hashrate > 0
            else { continue }
            scopes.append(
                SoloOutcomeScope(
                    id: device.id.uuidString,
                    title: device.name,
                    subtitle: "This miner's reported hashrate",
                    hashrateHPS: hashrate * 1e9
                )
            )
        }
        return scopes
    }

    func soloOutcomePage(scope: SoloOutcomeScope, difficulty: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(scope.title)
                    .fleetFont(.headline)
                    .lineLimit(1)
                Text("\(InsightsFormat.hashrate(scope.hashrateHPS)) · \(scope.subtitle)")
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("insights.soloOutcomeScope.\(scope.id)")
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(SoloOutcomeWindow.allCases) { window in
                    if let estimate = SoloMiningMath.estimate(
                        hashrateHPS: scope.hashrateHPS,
                        difficulty: difficulty,
                        duration: window.duration
                    ) {
                        GridRow {
                            Text(window.title)
                                .fleetFont(.caption, weight: .semibold)
                                .gridColumnAlignment(.leading)
                            let probText = Self.probabilityText(estimate)
                            Text(probText)
                                .fleetFont(.caption).monospacedDigit()
                                .fleetNumericUpdate(probText, reduceMotion: reduceMotion)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            let blocksText = Self.expectedBlocksText(estimate)
                            Text("\(blocksText) expected")
                                .fleetFont(.caption2).monospacedDigit()
                                .fleetNumericUpdate(blocksText, reduceMotion: reduceMotion)
                                .foregroundStyle(FleetTheme.secondary)
                                .multilineTextAlignment(.trailing)
                                .gridColumnAlignment(.trailing)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(soloOutcomeAccessibilityLabel(window: window, estimate: estimate))
                    }
                }
            }
            .accessibilityIdentifier("insights.soloOutcomeRows.\(scope.id)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func soloOutcomeAccessibilityLabel(window: SoloOutcomeWindow, estimate: SoloMiningEstimate) -> String {
        "\(window.accessibilityTitle), \(Self.probabilityText(estimate)), "
            + "\(Self.expectedBlocksText(estimate)) expected blocks"
    }

    static func probabilityText(_ estimate: SoloMiningEstimate) -> String {
        (estimate.probabilityAtLeastOne * 100).formatted(.number.precision(.significantDigits(3))) + "% chance"
    }

    static func expectedBlocksText(_ estimate: SoloMiningEstimate) -> String {
        estimate.expectedBlocks.formatted(.number.notation(.scientific).precision(.significantDigits(3)))
    }
}

#if os(macOS)
private struct MacSoloOutcomeSelector: View {
    let scopes: [SoloOutcomeScope]
    let page: (SoloOutcomeScope) -> AnyView
    @State private var selectedScopeID: String?

    private var selectedScope: SoloOutcomeScope? {
        scopes.first { $0.id == selectedScopeID } ?? scopes.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Hashrate scope", selection: Binding(
                get: { selectedScope?.id ?? "" },
                set: { selectedScopeID = $0 }
            )) {
                ForEach(scopes) { scope in
                    Text(scope.title).tag(scope.id)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("insights.soloOutcomeScopePicker")

            if let selectedScope {
                page(selectedScope)
            }
        }
        .accessibilityIdentifier("insights.soloOutcomePicker")
    }
}
#endif
