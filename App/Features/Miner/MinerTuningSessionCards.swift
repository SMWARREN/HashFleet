import SwiftUI
import HashFleetCore

/// One persisted line of the per-miner tuning journal.
struct MinerTuningJournalEntry: Codable, Hashable, Identifiable {
    let id: UUID
    let date: Date
    let title: String
    let detail: String
}

/// Read-only history of the last tuning actions for one miner.
struct MinerTuningJournalCard: View {
    nonisolated static let limit = 12

    let journal: [MinerTuningJournalEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Tuning journal", systemImage: "text.book.closed")
                    .fleetFont(.headline)
                Spacer()
                Text("Last 12")
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
            }
            if journal.isEmpty {
                Text("No tuning actions recorded yet. Applied setpoints and refreshed readings will appear here.")
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
            } else {
                ForEach(journal.prefix(Self.limit)) { entry in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: Self.isApplied(entry) ? "checkmark.circle.fill" : "circle.fill")
                            .foregroundStyle(Self.isApplied(entry) ? FleetTheme.positive : FleetTheme.accent)
                            .fleetFont(.caption)
                            .padding(.top, 3)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(entry.title)
                                    .fleetFont(.caption, weight: .semibold)
                                Spacer(minLength: 8)
                                Text(entry.date.formatted(date: .omitted, time: .shortened))
                                    .fleetFont(.caption2, design: .monospaced).monospacedDigit()
                                    .foregroundStyle(FleetTheme.secondary)
                            }
                            Text(entry.detail)
                                .fleetFont(.caption)
                                .foregroundStyle(FleetTheme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if entry.id != journal.prefix(Self.limit).last?.id {
                        Divider().overlay(FleetTheme.separator)
                    }
                }
            }
        }
        .fleetCard(padding: 16, fill: FleetTheme.raised.opacity(0.72))
        .accessibilityIdentifier("tuningSession.journal")
    }

    /// Older entries were titled "Frequency applied" before core voltage joined the session.
    private static func isApplied(_ entry: MinerTuningJournalEntry) -> Bool {
        entry.title == "Tuning applied" || entry.title == "Frequency applied"
    }
}

/// Persists the per-miner tuning journal in UserDefaults.
enum MinerTuningJournalStore {
    private static func key(_ deviceID: UUID) -> String {
        "app.hashfleet.tuningJournal.\(deviceID.uuidString)"
    }

    static func load(deviceID: UUID) -> [MinerTuningJournalEntry] {
        guard let data = UserDefaults.standard.data(forKey: key(deviceID)),
            let saved = try? JSONDecoder().decode([MinerTuningJournalEntry].self, from: data)
        else { return [] }
        return saved
    }

    /// Returns the new list with the entry first, trimmed to the journal limit, and saves it.
    static func record(
        title: String,
        detail: String,
        to journal: [MinerTuningJournalEntry],
        deviceID: UUID
    ) -> [MinerTuningJournalEntry] {
        let entry = MinerTuningJournalEntry(id: UUID(), date: Date(), title: title, detail: detail)
        let updated = Array(([entry] + journal).prefix(MinerTuningJournalCard.limit))
        if let data = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(data, forKey: key(deviceID))
        }
        return updated
    }
}

/// Risk acknowledgement stays separate from firmware references and device-specific restrictions.
struct MinerTuningSafetyCard: View {
    @Binding var riskAcknowledged: Bool
    let isBeyondReference: Bool
    let hasReference: Bool
    let voltageRestriction: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Safety gate", systemImage: "exclamationmark.triangle.fill")
                .fleetFont(.headline)
                .foregroundStyle(FleetTheme.warning)
            Text("Frequency and core voltage changes affect heat, power, stability and hardware life. "
                 + "Raising voltage raises power draw and temperature on a shared supply. Nothing is sent while you drag or tap.")
                .fleetFont(.footnote)
                .foregroundStyle(FleetTheme.secondary)
            Toggle("I understand the hardware and overheating risks", isOn: $riskAcknowledged)
                .fleetFont(.subheadline)
                .accessibilityIdentifier("tuningSession.riskAcknowledgement")
            if let voltageRestriction {
                Label(voltageRestriction, systemImage: "lock.shield.fill")
                    .fleetFont(.footnote, weight: .semibold)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("tuningSession.voltageRestriction")
            }
            if isBeyondReference {
                Label("Above the reported reference. Deliberate overclock review is required.",
                      systemImage: "exclamationmark.octagon.fill")
                    .fleetFont(.caption, weight: .semibold)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("tuningSession.overReferenceWarning")
            } else if hasReference {
                Label("Within the reported reference ceiling, not a safety certification.", systemImage: "checkmark.shield")
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.positive)
            }
        }
        .fleetCard(padding: 16, fill: isBeyondReference ? Color.red.opacity(0.08) : FleetTheme.surface,
                   border: isBeyondReference ? Color.red.opacity(0.55) : FleetTheme.ink.opacity(0.045))
    }
}

/// What the firmware itself reports about its frequency and voltage options. Never a safety limit.
struct MinerTuningReferenceCard: View {
    let reference: MinerTuningReference?
    let isDemo: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Firmware references", systemImage: "slider.horizontal.2.square")
                    .fleetFont(.headline)
                Spacer()
                if reference == nil && !isDemo {
                    Text("checking")
                        .fleetFont(.caption)
                        .foregroundStyle(FleetTheme.secondary)
                }
            }
            if let reference {
                if let model = reference.model, !model.isEmpty {
                    Text(model)
                        .fleetFont(.subheadline, weight: .semibold)
                        .foregroundStyle(FleetTheme.accent)
                }
                if !reference.frequencyOptions.isEmpty {
                    options(title: "Reported frequency options", values: reference.frequencyOptions, unit: "MHz")
                } else if let defaultFrequency = reference.defaultFrequency {
                    Text("Reported default: \(Self.formatted(defaultFrequency))")
                        .fleetFont(.caption)
                } else {
                    Text("No frequency reference was reported by this firmware.")
                        .fleetFont(.caption)
                        .foregroundStyle(FleetTheme.secondary)
                }
                if !reference.voltageOptions.isEmpty {
                    options(title: "Reported core-voltage options", values: reference.voltageOptions, unit: "mV")
                } else if let defaultVoltage = reference.defaultVoltage {
                    Text("Reported core default: \(Self.formatted(defaultVoltage, unit: "mV"))")
                        .fleetFont(.caption)
                } else {
                    Text("No core-voltage reference was reported by this firmware.")
                        .fleetFont(.caption)
                        .foregroundStyle(FleetTheme.secondary)
                }
                Text("Above-reference values turn red for deliberate review. "
                     + "References are not safety limits and never override a device restriction.")
                .fleetFont(.caption)
                .foregroundStyle(FleetTheme.warning)
            } else if isDemo {
                Text("Demo mode shows the controls without contacting a miner. No firmware reference is assumed.")
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
            } else {
                Text("The session is reading the miner's ASIC reference endpoint. Missing data stays visibly unknown.")
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
            }
        }
        .fleetCard(padding: 16, fill: FleetTheme.surface)
        .accessibilityIdentifier("tuningSession.references")
    }

    private static func formatted(_ value: Double, unit: String = "MHz") -> String {
        "\(MinerTuningDraft.numericText(value)) \(unit)"
    }

    private func options(title: String, values: [Double], unit: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .fleetFont(.caption, weight: .semibold)
                .foregroundStyle(FleetTheme.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        Text(Self.formatted(value, unit: unit))
                            .fleetFont(.caption2, weight: .semibold, design: .monospaced).monospacedDigit()
                            .foregroundStyle(FleetTheme.ink)
                            .fleetPillPadding()
                            .background(FleetTheme.raised, in: Capsule())
                    }
                }
            }
        }
    }
}

/// Title card: explains the session and shows the connection/read-only state.
struct MinerTuningSessionHeader: View {
    let deviceName: String
    let isDemo: Bool
    let isOffline: Bool
    let chipCount: Int
    let chipCountWasReported: Bool
    let controlMode: MinerTuningControlMode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(FleetTheme.accent.opacity(0.16))
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .fleetFont(.title2, weight: .semibold)
                        .foregroundStyle(FleetTheme.accent)
                }
                .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dyno tune")
                        .fleetFont(.title3, weight: .bold)
                    Text(deviceName)
                        .fleetFont(.subheadline, weight: .semibold)
                        .foregroundStyle(FleetTheme.accent)
                    Text(controlMode == .easy
                         ? "Choose a reported value or enter your own. Changes stay in the draft until you review and apply."
                         : "Drag the rim of a dial or tap the step buttons. The faint marker is what the miner runs now.")
                        .fleetFont(.footnote)
                        .foregroundStyle(FleetTheme.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                badge(
                    isDemo ? "DEMO" : (isOffline ? "READ ONLY" : "CONNECTED CHECK REQUIRED"),
                    color: isDemo || isOffline ? FleetTheme.warning : FleetTheme.positive,
                    symbol: isDemo || isOffline ? "lock.fill" : "checkmark.shield.fill"
                )
                badge("\(chipCount) ASIC\(chipCount == 1 ? "" : "s")", color: FleetTheme.accent, symbol: "number")
                if !chipCountWasReported {
                    Text("count not reported")
                        .fleetFont(.caption2, weight: .medium)
                        .foregroundStyle(FleetTheme.secondary)
                }
            }
        }
        .fleetCard(padding: 18, fill: FleetTheme.surface)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tuningSession.header")
    }

    private func badge(_ title: String, color: Color, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .fleetFont(.caption2, weight: .semibold)
            .foregroundStyle(color)
            .fleetPillPadding()
            .background(color.opacity(0.12), in: Capsule())
    }
}

/// Observational readings next to the dials. They never certify a safe setting.
struct MinerTuningLiveContextCard: View {
    let configuredFrequency: String
    let measuredFrequency: String
    let configuredVoltage: String
    let measuredVoltage: String
    let asicErrors: String
    let isChecking: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Live context", systemImage: "dot.radiowaves.left.and.right")
                    .fleetFont(.headline)
                Spacer()
                if isChecking { ProgressView().controlSize(.small) }
            }
            HStack(spacing: 10) {
                metric("Configured", configuredFrequency)
                metric("Measured", measuredFrequency)
                metric("ASIC errors", asicErrors)
            }
            HStack(spacing: 10) {
                metric("Core set", configuredVoltage)
                metric("Core measured", measuredVoltage)
                Color.clear.frame(maxWidth: .infinity)
            }
            Text(
                "These readings are observational. They do not certify a safe frequency, voltage, power supply or cooling setup."
            )
            .fleetFont(.caption)
            .foregroundStyle(FleetTheme.secondary)
        }
        .fleetCard(padding: 16, fill: FleetTheme.raised.opacity(0.72))
        .accessibilityIdentifier("tuningSession.liveContext")
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .fleetFont(.caption2, weight: .semibold)
                .foregroundStyle(FleetTheme.secondary)
            Text(value)
                .fleetFont(.subheadline, weight: .semibold, design: .monospaced).monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
