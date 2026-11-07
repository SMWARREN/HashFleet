import SwiftUI

struct FleetEnergyView: View {
    let store: FleetStore
    @State private var settings: FleetEnergySettings
    @State private var rateText: String
    @State private var currency: String
    @State private var feedback: String?
    @FocusState private var editingRate: Bool

    init(store: FleetStore) {
        self.store = store
        let settings = FleetEnergySettings(defaults: store.defaults)
        _settings = State(initialValue: settings)
        _currency = State(initialValue: settings.currency)
        _rateText = State(initialValue: settings.rate.map {
            FleetEnergySettings.editableRate($0)
        } ?? "")
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { _ in
            let estimate = FleetEnergyEstimate.capture(store: store)
            FleetSettingsForm {
                FleetSettingsSection {
                    FleetSettingsRow(showsSeparator: false) {
                        BitsySays(
                            mood: .thinking,
                            message: "I'll turn your miner's power reading into an electricity estimate.",
                            size: 68
                        )
                        .accessibilityIdentifier("energy.bitsy")
                    }
                }
                .fleetSettingsSectionIdentifier("energy.introSection")
                .fleetSectionFullWidth()
                FleetSettingsSection(content: {
                    FleetSettingsRow {
                        TextField("Price per kWh", text: $rateText)
                            #if os(macOS)
                            .textFieldStyle(.plain)
                            #endif
                            .keyboardType(.decimalPad)
                            .focused($editingRate)
                            .accessibilityLabel("Electricity price per kilowatt-hour")
                            .accessibilityIdentifier("energy.rateField")
                    }
                    FleetSettingsRow {
                        FleetSettingsPicker("Currency", valueTitle: currency,
                            selection: $currency, valueColor: FleetTheme.accent) {
                            ForEach(FleetEnergySettings.currencies, id: \.self) { Text($0).tag($0) }
                        }
                        .accessibilityIdentifier("energy.currencyPicker")
                    }
                    FleetSettingsRow {
                        Button("Save electricity rate") {
                            do {
                                try settings.save(rateText: rateText, currency: currency)
                                feedback = "Rate saved on this device. Miner settings are unchanged."
                                editingRate = false
                            } catch { feedback = error.localizedDescription }
                        }
                        .accessibilityIdentifier("energy.save")
                    }
                    if let feedback {
                        FleetSettingsRow(showsSeparator: false) {
                            Text(feedback).fleetFont(.footnote).accessibilityIdentifier("energy.feedback")
                        }
                    }
                }, header: {
                    HStack(alignment: .center, spacing: 10) {
                        Text("Your electricity rate")
                        Spacer(minLength: 8)
                        FleetEnergyIllustration(size: 64)
                    }
                }, footer: {
                    Text("Enter the price per kWh in your chosen currency, for example 0.15 USD for 15 cents. "
                        + "No currency conversion happens, no cloud service is contacted, and no miner command "
                        + "is sent.")
                })
                .fleetSettingsSectionIdentifier("energy.rateSection")
                FleetSettingsSection(content: {
                    if estimate.isDemo {
                        FleetSettingsRow {
                            Label("Demo / simulated power", systemImage: "flask")
                                .foregroundStyle(FleetTheme.warning)
                        }
                    }
                    FleetSettingsRow {
                        LabeledContent("Fresh power subtotal", value: quantity(estimate.watts, unit: "W"))
                            .accessibilityIdentifier("energy.measuredPowerValue")
                    }
                    FleetSettingsRow {
                        Text("\(estimate.reportingCount) of \(estimate.deviceCount) miners have fresh power readings.")
                            .fleetFont(.footnote)
                            .accessibilityIdentifier("energy.coverageLabel")
                    }
                    if estimate.reportingCount < estimate.deviceCount {
                        FleetSettingsRow {
                            Text("Partial estimate: miners whose readings are missing, offline, cached or older than two minutes are not counted. This is not the whole fleet's cost.")
                                .fleetFont(.footnote).foregroundStyle(FleetTheme.warning)
                        }
                    }
                    let dailyEnergy = quantity(estimate.dailyKWh, unit: "kWh")
                    FleetSettingsRow {
                        LabeledContent("Projected daily energy") {
                            Text(dailyEnergy).fleetNumericUpdate(dailyEnergy)
                        }
                        .accessibilityIdentifier("energy.dailyKWhValue")
                    }
                    let dailyCost = money(estimate.dailyCost(rate: settings.rate))
                    FleetSettingsRow {
                        LabeledContent("Projected daily cost") {
                            Text(dailyCost).fleetNumericUpdate(dailyCost)
                        }
                        .accessibilityIdentifier("energy.dailyCostValue")
                        .fleetTourTarget("guide.dailyCost")
                    }
                    let monthlyCost = money(estimate.monthlyCost(rate: settings.rate))
                    FleetSettingsRow {
                        LabeledContent("Projected 30-day cost") {
                            Text(monthlyCost).fleetNumericUpdate(monthlyCost)
                        }
                        .accessibilityIdentifier("energy.monthlyCostValue")
                    }
                }, header: {
                    Text("At the current load")
                }, footer: {
                    Text("Projections assume the power being reported right now stays constant around the clock. "
                        + "They are not metered consumption, bills, mining revenue or profit. Supply losses, "
                        + "other equipment, standing charges and tariff changes are not included.")
                        .accessibilityIdentifier("energy.disclaimerLabel")
                })
                .fleetSettingsSectionIdentifier("energy.estimateSection")
                FleetEnergyHistorySection(store: store, rate: settings.rate, currency: settings.currency)
            }
            .scrollContentBackground(.hidden)
            .background(FleetTheme.canvas)
        }
        .tint(FleetTheme.accent)
        .fleetAppNavigation { $0.navigationTitle("Electricity estimates") }
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("energy.view")
    }

    private func quantity(_ value: Double?, unit: String) -> String {
        value.map { "\($0.formatted(.number.precision(.fractionLength(0...3)))) \(unit)" } ?? "Not reported"
    }
    private func money(_ value: Double?) -> String {
        guard settings.rate != nil else { return "Set your rate" }
        return value.map { $0.formatted(.currency(code: settings.currency)) } ?? "Not reported"
    }
}
