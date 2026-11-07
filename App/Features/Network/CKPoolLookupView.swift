import SwiftUI
import HashFleetCore

struct CKPoolLookupView: View {
    let insights: MiningInsightsStore
    var externalDataEnabled: Bool = true
    @State private var address = ""
    @State private var submittedAddress: String?
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var addressFocused: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { timeline in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FleetSectionLabel(
                        title: "Your side of the pool",
                        subtitle:
                            "Read CKPool's public account statistics without changing your miner's pool configuration."
                    )
                    VStack(alignment: .leading, spacing: 12) {
                        Text("CKPool payout address").fleetFont(.headline)
                        TextField("Bitcoin address, without .worker", text: $address)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .keyboardType(.asciiCapable).textFieldStyle(.roundedBorder)
                            .focused($addressFocused)
                            .submitLabel(.done)
                            .onSubmit { addressFocused = false }
                            .accessibilityIdentifier("poolLookup.address")
                            .privacySensitive()
                        Text(
                            "Tapping Look up sends only this address to raw.stats.ckpool.org over HTTPS. "
                                + "CKPool will see it and your internet IP. Nothing is read from your miner settings, "
                                + "saved to disk, or sent automatically. "
                                + "Never enter a seed phrase, private key or pool password."
                        )
                        .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
                        Button {
                            addressFocused = false
                            submittedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
                            Task { await insights.lookup(address: address) }
                        } label: {
                            HStack {
                                if insights.isLookingUp { ProgressView() }
                                Text("Look up CKPool statistics")
                            }.frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.borderedProminent).foregroundStyle(FleetTheme.buttonInk)
                        .disabled(
                            !externalDataEnabled || insights.isDemo
                                || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || insights.isLookingUp || timeline.date < insights.lookupAvailableAt
                        )
                        .accessibilityIdentifier("poolLookup.submit")
                        if insights.isDemo {
                            Text("Address lookup is disabled in demo. No address is sent.").fleetFont(.caption)
                                .foregroundStyle(FleetTheme.accent)
                        } else if timeline.date < insights.lookupAvailableAt {
                            Text("Lookups are limited to once per minute.").fleetFont(.caption).foregroundStyle(
                                FleetTheme.secondary
                            )
                        }
                    }.fleetCard()
                    if let result = insights.userLookup {
                        lookupResult(result, now: timeline.date)
                    }
                    Text(
                        "CKPool's hashrate is estimated from pool-side shares and can differ from your miner's "
                            + "short-window reading. Shares here are CKPool's reported counter, not necessarily the "
                            + "miner's accepted-share count. No wallet balance or expected payout is inferred. "
                            + "An address used at another pool may have no CKPool record."
                    )
                    .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
                }
                .fleetPageContainer(compactMaxWidth: FleetLayout.listContentWidth)
            }
        }
        .background(FleetTheme.canvas).foregroundStyle(FleetTheme.ink)
        .navigationTitle("CKPool lookup").navigationBarTitleDisplayMode(.inline)
        .onChange(of: address) { _, _ in
            insights.clearLookup(); submittedAddress = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { insights.clearLookup(); address = ""; submittedAddress = nil }
        }
        .onDisappear {
            insights.clearLookup(); address = ""; submittedAddress = nil
        }
    }

    @ViewBuilder private func lookupResult(_ lookup: CKPoolUserLookup, now: Date) -> some View {
        switch lookup {
        case .found(let result):
            InsightsSourceCard(title: "CKPool account", result: result, isDemo: false, now: now) { value in
                if let submittedAddress {
                    Text(submittedAddress).fleetFont(.caption, design: .monospaced).lineLimit(2).privacySensitive()
                }
                InsightsRow("Hashrate · 5 minutes", value: InsightsFormat.hashrate(value.hashrate5MinutesHPS))
                InsightsRow("Hashrate · 1 hour", value: InsightsFormat.hashrate(value.hashrate1HourHPS))
                InsightsRow("Hashrate · 1 day", value: InsightsFormat.hashrate(value.hashrate1DayHPS))
                InsightsRow("Hashrate · 7 days", value: InsightsFormat.hashrate(value.hashrate7DaysHPS))
                InsightsRow("Workers", value: value.workers?.formatted() ?? "Not reported")
                InsightsRow(
                    "Pool-reported shares",
                    value: value.shares.map { InsightsFormat.compact($0) } ?? "Not reported"
                )
                InsightsRow("Best share", value: value.bestShare.map { InsightsFormat.compact($0) } ?? "Not reported")
                InsightsRow("Best ever", value: value.bestEver.map { InsightsFormat.compact($0) } ?? "Not reported")
                InsightsRow(
                    "Last share",
                    value: value.lastShareAt?.formatted(date: .abbreviated, time: .standard) ?? "Not reported"
                )
            }.accessibilityIdentifier("poolLookup.result")
        case .notFound:
            Text(
                "No CKPool statistics found for this address. This does not mean your miner or another pool is offline."
            )
            .fleetCard().accessibilityIdentifier("poolLookup.notFound")
        case .failed(let error):
            VStack(alignment: .leading, spacing: 8) {
                Label("Lookup unavailable", systemImage: "exclamationmark.circle")
                Text(error.localizedDescription)
            }.foregroundStyle(FleetTheme.warning).fleetCard().accessibilityIdentifier("poolLookup.error")
        }
    }
}

#Preview("CKPool lookup") {
    NavigationStack {
        CKPoolLookupView(insights: MiningInsightsStore(), externalDataEnabled: true)
    }
}
