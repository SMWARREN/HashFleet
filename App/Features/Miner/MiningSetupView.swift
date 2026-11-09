import SwiftUI
import HashFleetCore

/// Compact guided pool and coin setup view for Bitaxe, AxeOS and other compatible open-source miners.
/// Guides miners through selecting SHA-256d coins, solo vs shared pool mode, and safe slot drafting.
/// Never performs writes automatically: selection populates a local draft that requires full-slot replacement
/// acknowledgement and exact JSON inspection before confirmation.
public struct MiningSetupView: View {
    let device: MinerDevice
    @Bindable var store: FleetStore
    var insights: MiningInsightsStore?
    let onSelectPreset: (MiningPoolPreset) -> Void

    @State private var selectedMode: PoolOperationMode = .solo
    @State private var selectedCoin: MiningCoin = .btc
    @Environment(\.dismiss) private var dismiss

    init(
        device: MinerDevice,
        store: FleetStore,
        insights: MiningInsightsStore? = nil,
        onSelectPreset: @escaping (MiningPoolPreset) -> Void
    ) {
        self.device = device
        self.store = store
        self.insights = insights
        self.onSelectPreset = onSelectPreset
    }

    private var info: MinerInfo? { store.snapshot(for: device.id)?.info }
    private var reportedASIC: String? {
        if let asicObject = store.capabilities.reports[device.id]?.asic?.objectValue,
            let model = asicObject["ASICModel"]?.stringValue
                ?? asicObject["asicModel"]?.stringValue
                ?? asicObject["model"]?.stringValue,
            !model.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            return model
        }
        return info?.asicModel
    }

    private var compatibility: MiningHardwareCompatibility {
        selectedCoin.checkCompatibility(reportedASIC: reportedASIC)
    }

    private var availablePresets: [MiningPoolPreset] {
        MiningSetupCatalog.allPresets.filter {
            $0.mode == selectedMode && $0.coin == selectedCoin
        }
    }

    public var body: some View {
        FleetSettingsForm {
            FleetSettingsSection {
                Text(
                    "Set up solo or shared mining with verified"
                        + " SHA-256d endpoints. Choosing a preset fills"
                        + " your miner pool draft safely. Nothing is"
                        + " saved until you review the exact JSON."
                )
                .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
            }
            .listRowBackground(FleetTheme.surface)

            FleetSettingsSection("1. Mining Mode") {
                Picker("Mode", selection: $selectedMode) {
                    ForEach(PoolOperationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("miningSetup.modePicker")

                Text(selectedMode.description)
                    .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
            }
            .listRowBackground(FleetTheme.surface)

            FleetSettingsSection("2. Mineable Coin (SHA-256d)") {
                Picker("Coin", selection: $selectedCoin) {
                    ForEach(MiningCoin.allCases) { coin in
                        Text("\(coin.symbol) · \(coin.fullName)").tag(coin)
                    }
                }
                .accessibilityIdentifier("miningSetup.coinPicker")

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(selectedCoin.fullName)
                            .fleetFont(.subheadline, weight: .medium)
                            .foregroundStyle(FleetTheme.ink)
                        Spacer()
                        priceBadge
                    }
                    Text(selectedCoin.plainEnglishDescription)
                        .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)

                    HStack(spacing: 6) {
                        Image(
                            systemName: compatibility.isCompatible ? "checkmark.shield.fill" : "questionmark.shield"
                        )
                        .foregroundStyle(compatibility.isCompatible ? FleetTheme.accent : FleetTheme.warning)
                        Text(compatibility.statusBadge)
                            .fleetFont(.caption, weight: .medium)
                            .foregroundStyle(compatibility.isCompatible ? FleetTheme.accent : FleetTheme.warning)
                    }
                    .padding(.top, 2)

                    Text(compatibility.description)
                        .fleetFont(.caption2).foregroundStyle(FleetTheme.secondary)
                }
                .padding(.vertical, 4)

                Text(CoinPriceQuote.profitabilityDisclaimer)
                    .fleetFont(.caption2).foregroundStyle(FleetTheme.secondary)
            }
            .listRowBackground(FleetTheme.surface)

            FleetSettingsSection("3. Verified Endpoints") {
                if availablePresets.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            "No official"
                                + " \(selectedMode.rawValue.lowercased())"
                                + " presets available"
                                + " for \(selectedCoin.symbol)."
                        )
                        .fleetFont(.subheadline).foregroundStyle(FleetTheme.ink)
                        Text("You can manually configure any Stratum V1 endpoint in the pool connection form.")
                            .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(availablePresets) { preset in
                        presetRow(preset)
                    }
                }
            }
            .listRowBackground(FleetTheme.surface)
        }
        .navigationTitle("Guided Pool Setup")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(FleetTheme.canvas)
        .tint(FleetTheme.accent)
    }

    @ViewBuilder
    private var priceBadge: some View {
        TimelineView(.periodic(from: .now, by: 15)) { timeline in
            let quote = selectedCoin.publicPriceUSD(from: insights, now: timeline.date)
            let isDemo = store.isDemo
            switch quote {
            case .fresh(let usd, let source):
                Text("\(isDemo ? "DEMO · " : "")$\(usd.formatted(.number.precision(.fractionLength(2)))) (\(source))")
                    .fleetFont(.caption, weight: .medium, design: .monospaced)
                    .foregroundStyle(FleetTheme.accent)
                    .fleetPillPadding()
                    .background(FleetTheme.accent.opacity(0.12), in: Capsule())
            case .stale(let usd, let source):
                let staleLabel =
                    "\(isDemo ? "DEMO · " : "")"
                    + "$\(usd.formatted(.number.precision(.fractionLength(2))))"
                    + " (stale · \(source))"
                Text(staleLabel)
                    .fleetFont(.caption, design: .monospaced).monospacedDigit()
                    .foregroundStyle(FleetTheme.warning)
                    .fleetPillPadding()
                    .background(FleetTheme.warning.opacity(0.12), in: Capsule())
            case .unavailable:
                Text("Price unavailable")
                    .fleetFont(.caption2)
                    .foregroundStyle(FleetTheme.secondary)
                    .fleetPillPadding()
                    .background(FleetTheme.surface, in: Capsule())
            }
        }
    }

    private func presetRow(_ preset: MiningPoolPreset) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .fleetFont(.headline).foregroundStyle(FleetTheme.ink)
                    Text(preset.endpointLabel)
                        .fleetFont(.caption, design: .monospaced).foregroundStyle(FleetTheme.secondary)
                }
                Spacer()
                Button("Use Preset") {
                    onSelectPreset(preset)
                    dismiss()
                }
                .buttonStyle(.borderedProminent).foregroundStyle(FleetTheme.buttonInk)
                .tint(FleetTheme.accent)
                .accessibilityIdentifier("miningSetup.usePreset.\(preset.id)")
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(preset.credentialGuidance.prompt)
                    .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
                Text(preset.feeDescription)
                    .fleetFont(.caption2).foregroundStyle(FleetTheme.secondary)
            }
            .padding(.top, 2)

            Link("Official documentation & setup guide", destination: preset.documentationURL)
                .fleetFont(.caption)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("miningSetup.presetCard.\(preset.id)")
    }
}

#Preview("Guided pool setup · demo") {
    let store = FleetStore(defaults: UserDefaults(suiteName: "app.hashfleet.mining-setup-preview")!)
    store.loadDemo()
    return NavigationStack {
        MiningSetupView(device: store.devices[0], store: store, onSelectPreset: { _ in })
    }
}
