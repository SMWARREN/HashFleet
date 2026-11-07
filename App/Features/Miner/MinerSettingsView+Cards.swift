import SwiftUI
import HashFleetCore

/// Settings hub UI cards: quick changes, one control index, and read-only sections.
/// Extracted to reduce MinerSettingsView struct body length.
extension MinerSettingsView {

    private var quickChangesSaveDirectly: Bool {
        guard let review = quickChangesReview else { return true }
        return MinerDirectSavePolicy.qualifies(
            endpoint: .settings,
            payload: review.payload
        )
    }

    var quickChangesCard: some View {
        let canSaveDirectly = quickChangesSaveDirectly
        return settingsHubCard {
            settingsHubHeader(
                "Quick changes",
                subtitle: "Network hostname and on-device history.",
                symbol: "wand.and.stars"
            )
            Divider().overlay(FleetTheme.separator)
            Text(
                canSaveDirectly
                    ? "Nothing is sent while you edit. Tap Save to send your changes to the miner."
                    : "Nothing is sent while you edit. Review opens the exact combined JSON request, "
                        + "then you confirm the risk before sending."
            )
            .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)

            HStack {
                Text("Network hostname").foregroundStyle(FleetTheme.ink)
                Spacer()
                TextField("Network hostname", text: $hostname)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(offlineReadOnly)
                    .accessibilityIdentifier("settings.quick.hostname")
            }
            .fleetFont(.subheadline)
            .padding(.vertical, 7)
            .overlay(alignment: .bottom) { Divider().overlay(FleetTheme.separator) }

            HStack {
                Text("On-device history").foregroundStyle(FleetTheme.ink)
                Spacer()
                Picker("On-device history", selection: $statsFrequency) {
                    Text("Leave unchanged").tag(Optional<Int>.none)
                    ForEach(
                        MinerTuningDraft.statsFrequencyOptions(reported: reportedFields?["statsFrequency"]),
                        id: \.self
                    ) { seconds in
                        Text(MinerTuningDraft.statsFrequencyLabel(seconds)).tag(Optional(seconds))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize(horizontal: true, vertical: false)
                .disabled(offlineReadOnly)
                .accessibilityIdentifier("settings.quick.statsFrequency")
            }
            .fleetFont(.subheadline)
            .padding(.vertical, 7)
            .overlay(alignment: .bottom) { Divider().overlay(FleetTheme.separator) }

            quickChangesSummary

            if let review = quickChangesReview,
                let text = try? review.payload.prettyPrinted() {
                DisclosureGroup("Request details (JSON)") {
                    Text(MinerRequestSafety.reviewedBody(Data(text.utf8)))
                        .fleetFont(.caption, design: .monospaced)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("settings.quick.requestDetails")
            }

            Button(
                canSaveDirectly ? "Save changes" : "Review common changes",
                systemImage: "checkmark.circle"
            ) { reviewQuickChanges() }
                .buttonStyle(.borderedProminent)
                .tint(FleetTheme.accent)
                .foregroundStyle(FleetTheme.buttonInk)
                .frame(maxWidth: .infinity)
                .padding(.top, 5)
                .disabled(store.isDemo || offlineReadOnly || isSaving)
                .accessibilityIdentifier("settings.quick.review")
            directSaveStatus
                .frame(maxWidth: .infinity, alignment: .center)
            Text(
                "Only values that differ from the last complete miner reading are included. "
                + "Cooling, frequency and voltage, pools, display, and tools each have one dedicated category."
            )
            .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
        }
    }

    private var quickChangesReview: MinerSettingsReview? {
        try? MinerSettingsReview(
            original: info,
            hostname: hostname,
            statsFrequency: statsFrequency,
            autoFan: info?.raw["autofanspeed"]?.boolValue ?? autoFan,
            temperatureTarget: MinerTuningDraft.integerDraft(from: info?.raw["temptarget"])
        )
    }

    private var quickChangesSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let review = quickChangesReview {
                Text(
                    review.changes.count == 1
                        ? "1 pending change"
                        : "\(review.changes.count) pending changes"
                )
                .fleetFont(.subheadline, weight: .semibold)
                .foregroundStyle(FleetTheme.ink)

                ForEach(review.changes, id: \.key) { change in
                    quickChangeRow(change)
                }
            } else {
                Text("0 pending changes")
                    .fleetFont(.subheadline, weight: .semibold)
                    .foregroundStyle(FleetTheme.secondary)
                Text(
                    quickChangesSaveDirectly
                        ? "Adjust a value above, then tap Save."
                        : "Adjust a value above to prepare a reviewed change."
                )
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FleetSurfaceSpacing.cardInset)
        .background(FleetTheme.raised.opacity(0.42), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.quick.changes")
    }

    private func quickChangeRow(_ change: MinerSettingsReview.Change) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(change.title)
                .fleetFont(.caption, weight: .semibold)
                .foregroundStyle(FleetTheme.ink)
            HStack(spacing: 6) {
                Text(change.previousValue)
                    .foregroundStyle(FleetTheme.secondary)
                    .lineLimit(2)
                Image(systemName: "arrow.right")
                    .fleetFont(.caption2, weight: .semibold)
                    .foregroundStyle(FleetTheme.accent)
                    .accessibilityHidden(true)
                Text(change.value)
                    .foregroundStyle(FleetTheme.ink)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .fleetFont(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) { Divider().overlay(FleetTheme.separator) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.quick.change.\(change.key)")
    }

    var reportedStateCard: some View {
        let diagnostics = MinerDiagnosticsModel(info: info ?? MinerInfo(raw: [:]))
        let freshness = MinerSnapshotFreshness(updatedAt: store.snapshot(for: device.id)?.updatedAt)

        return settingsHubCard {
            settingsHubHeader(
                "Reported state",
                subtitle: "Read-only values reported by this miner.",
                symbol: "waveform.path.ecg"
            )
            Divider().overlay(FleetTheme.separator)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: store.isDemo ? "lock.fill" : "clock")
                    .foregroundStyle(FleetTheme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.isDemo ? "Demo sample · read only" : reportedStateSource(freshness))
                        .fleetFont(.caption, weight: .semibold)
                        .foregroundStyle(FleetTheme.ink)
                    Text(
                        store.isDemo
                            ? "No miner was contacted for this sample."
                            : "Values are observations, not safety or supervisor conclusions."
                    )
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("settings.reportedState.source")

            VStack(spacing: 7) {
                reportedStateRow(
                    "ASIC / board",
                    MinerCapabilityPresentation.asicDescriptor(info: info) ?? diagnostics.system.boardVersion ?? "Not reported",
                    id: "settings.reportedState.identity"
                )
                reportedStateRow(
                    "Firmware",
                    diagnostics.system.firmwareVersion ?? diagnostics.system.axeOSVersion ?? "Not reported",
                    id: "settings.reportedState.firmware"
                )
                reportedStateRow(
                    "Frequency (configured)",
                    MinerDiagnosticsModel.formatFrequency(diagnostics.electrical.configuredFrequencyMHz),
                    id: "settings.reportedState.frequency.configured"
                )
                reportedStateRow(
                    "Frequency (measured)",
                    MinerDiagnosticsModel.formatFrequency(diagnostics.electrical.actualFrequencyMHz),
                    id: "settings.reportedState.frequency.measured"
                )
                reportedStateRow(
                    "Core voltage (configured)",
                    MinerDiagnosticsModel.formatMillivolts(diagnostics.electrical.configuredCoreVoltageMV),
                    id: "settings.reportedState.voltage.configured"
                )
                reportedStateRow(
                    "Core voltage (measured)",
                    MinerDiagnosticsModel.formatMillivolts(diagnostics.electrical.actualCoreVoltageMV),
                    id: "settings.reportedState.voltage.measured"
                )
                reportedStateRow(
                    "Primary chip temperature",
                    MinerDiagnosticsModel.formatTemperature(diagnostics.thermal.primaryChipTempCelsius),
                    id: "settings.reportedState.temperature.primary"
                )
                reportedStateRow(
                    "VR / regulator temperature",
                    MinerDiagnosticsModel.formatTemperature(diagnostics.thermal.vrTempCelsius),
                    id: "settings.reportedState.temperature.vr"
                )
                reportedStateRow(
                    "Fan control",
                    MinerDiagnosticsModel.formatPercentage(diagnostics.thermal.fanSpeedPercent, decimals: 0),
                    id: "settings.reportedState.fan.percent"
                )
                reportedStateRow(
                    "Primary fan",
                    MinerDiagnosticsModel.formatFanRPM(diagnostics.thermal.fan1RPM),
                    id: "settings.reportedState.fan.rpm"
                )
                reportedStateRow(
                    "ASIC hardware errors",
                    MinerDiagnosticsModel.formatPercentage(diagnostics.hashrate.asicErrorPercentage),
                    id: "settings.reportedState.hardwareErrors"
                )
            }

            MinerDiagnosticsView(model: diagnostics)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.reportedState")
    }

    private func reportedStateSource(_ freshness: MinerSnapshotFreshness?) -> String {
        let snapshot = store.snapshot(for: device.id)
        let age = freshness?.summary ?? "Age unavailable"
        if snapshot?.isCached == true {
            return "Cached reading · \(age) · read only"
        }
        if snapshot?.error != nil {
            return "Last known reading · \(age) · read only"
        }
        if snapshot?.isReconnecting == true {
            return "Reconnecting · last reading · \(age) · read only"
        }
        guard let freshness else { return "No current reading · read only" }
        return freshness.isStale
            ? "Reported reading may be stale · \(freshness.summary) · read only"
            : "Reported reading · \(freshness.summary) · read only"
    }

    private func reportedStateRow(_ title: String, _ value: String, id: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).foregroundStyle(FleetTheme.secondary)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(FleetTheme.ink)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .fleetFont(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    var controlsCard: some View {
        settingsHubCard {
            settingsHubHeader(
                "Controls",
                subtitle: "One route for each miner task. Review appears only when needed.",
                symbol: "slider.horizontal.3"
            )
            Divider().overlay(FleetTheme.separator)
            settingsHubCategory(
                "General",
                subtitle: "Device name and on-device statistics",
                symbol: "gearshape",
                id: "settings.general"
            ) { AnyView(generalPage) }
            settingsHubCategory(
                "Pools",
                subtitle: "Manage your mining connections",
                symbol: "network",
                id: "settings.pools"
            ) { AnyView(poolsPage) }
            settingsHubCategory(
                "Display",
                subtitle: "Make the miner's screen your own",
                symbol: "display",
                id: "settings.display"
            ) { AnyView(displayPage) }
            settingsHubCategory(
                "Cooling",
                subtitle: "Automatic fan, speed and temperature",
                symbol: "fan",
                id: "settings.cooling"
            ) { AnyView(coolingPage) }
            settingsHubCategory(
                "Frequency & voltage",
                subtitle: "Live readings and board-wide tuning",
                symbol: "gauge.with.dots.needle.67percent",
                id: "settings.tuning"
            ) { AnyView(tuningPage) }
            settingsHubCategory(
                "Tools & firmware",
                subtitle: "Diagnostics, firmware and request JSON",
                symbol: "wrench.and.screwdriver",
                id: "settings.advanced"
            ) { AnyView(advancedPage) }
            NavigationLink {
                MinerEndpointView(device: device, store: store, endpoint: .restart, insights: insights)
            } label: {
                Label("Restart miner", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("settings.restart")
            .accessibilityHint("Opens a review. Restart is sent only after you confirm.")
        }
    }

    var compatibilityCard: some View {
        NavigationLink {
            MinerCompatibilityView(device: device, store: store, insights: insights)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal").foregroundStyle(FleetTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Check compatibility").foregroundStyle(FleetTheme.ink)
                    Text(compatibilitySubtitle).fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(FleetTheme.secondary)
            }
        }
        .accessibilityIdentifier("settings.compatibility")
        .padding(.horizontal, 4)
    }
}
