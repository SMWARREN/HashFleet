import SwiftUI
import HashFleetCore

extension MinerSettingsView {
    var generalPage: some View {
            proposalPage("General", subtitle: "Network identity and on-device history.") {
            settingsHubCard {
                settingsHubHeader(
                        "Network identity",
                        subtitle: "Hostname used to reach this miner on your network.",
                    symbol: "person.crop.circle"
                )
                Divider().overlay(FleetTheme.separator)
                Text("Network hostname").fleetFont(.subheadline).foregroundStyle(FleetTheme.ink)
                TextField("Network hostname", text: $hostname)
                    .focused(editingFocus, equals: .hostname)
                    .submitLabel(.done)
                    .onSubmit { editingFocus.wrappedValue = nil }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("settings.general.hostname")
                    .id(EditingField.hostname)
                Text("Used to identify this miner on your network.")
                    .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
                fieldNote("hostname", label: "the device name")
                proposalReviewButton(everydayTitle(review: "Review hostname change", save: "Save name")) {
                    guard !hostname.isEmpty, hostname.range(of: "^[a-zA-Z0-9-]+$", options: .regularExpression) != nil
                    else {
                        error = "Hostname may contain only letters, digits and hyphens."
                        return
                    }
                    submit(.settings, object: ["hostname": hostname])
                }
                if !savesDirectly {
                    Text("Review and confirm before sending to your miner.")
                        .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .fleetStaggeredEntrance(index: 0, reduceMotion: reduceMotion)

            settingsHubCard {
                settingsHubHeader(
                    "On-device history",
                    subtitle: "Stored by miner firmware, separate from app refresh.",
                    symbol: "clock"
                )
                Divider().overlay(FleetTheme.separator)
                Text("Statistics interval").fleetFont(.subheadline).foregroundStyle(FleetTheme.ink)
                Picker("Statistics interval", selection: $statsFrequency) {
                    Text("Choose an interval").tag(Optional<Int>.none)
                    ForEach(
                        MinerTuningDraft.statsFrequencyOptions(reported: reportedFields?["statsFrequency"]),
                        id: \.self
                    ) { seconds in
                        Text(MinerTuningDraft.statsFrequencyLabel(seconds)).tag(Optional(seconds))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                fieldNote("statsFrequency", label: "the statistics interval")
                if let statsFrequency, let history = MinerTuningDraft.statsHistoryLabel(statsFrequency) {
                    Text(
                        ("The miner keeps roughly \(MinerTuningDraft.statsHistorySampleCount) samples, "
                        + "about \(history) of history at this interval. "
                            + "Thinning is approximate and history is lost on restart.")
                    )
                    .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
                }
                Text(
                    ("This is the miner\'s own statistics logging, stored on the device and read by its charts. "
                    + "It is separate from the app's optional Realtime miner readings setting in Fleet preferences. "
                        + "Disabled frees the on-device buffer and stops logging. Firmware support varies.")
                )
                .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
                proposalReviewButton(everydayTitle(review: "Review statistics interval", save: "Save interval")) {
                    do { submit(.settings, json: try MinerTuningDraft.statsFrequencyPayload(statsFrequency)) } catch {
                        self.error = error.localizedDescription
                    }
                }
                if !savesDirectly {
                    Text("Review and confirm before sending to your miner.")
                        .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .fleetStaggeredEntrance(index: 1, reduceMotion: reduceMotion)
        }
    }

    var coolingPage: AnyView {
        if usesCoolingPreview {
            if NumberFirstPreview.usesLivePhoneLayouts && !store.isDemo {
                let destination = MinerCoolingPreview.LiveDestination(
                    target: "\(device.name) (\(device.address))", save: saveLiveCooling
                )
                return AnyView(MinerCoolingPreview(
                    mode: store.preferences.dashboardMode, info: info, canEdit: canWriteLiveCooling, live: destination
                ).id(device))
            }
            let canEdit = info.map { NumberFirstPreview.minerAvailability($0).cooling } == true
            return AnyView(MinerCoolingPreview(mode: store.preferences.dashboardMode, info: info, canEdit: canEdit))
        }
        return AnyView(reviewedCoolingPage)
    }

    private var canWriteLiveCooling: Bool {
        guard NumberFirstPreview.usesLivePhoneLayouts, usesCoolingPreview, !store.isDemo,
              device.kind != .xmrig, store.visibleDevices.contains(where: {
                  $0.id == device.id && $0.address == device.address && $0.kind == device.kind
              }), let info, NumberFirstPreview.minerAvailability(info, device: device, store: store).cooling
        else { return false }
        return MinerWriteAvailability.allows(
            store.snapshot(for: device.id), device: device, currentDevices: store.visibleDevices, isDemo: store.isDemo
        )
    }

    private func saveLiveCooling(
        from baseline: MinerCoolingPreviewDraft, to requested: MinerCoolingPreviewDraft
    ) async throws -> MinerCoolingPreviewDraft {
        guard canWriteLiveCooling, MinerCoolingPreviewDraft(info: info) == baseline,
              let identity = info.flatMap(MinerInlineActionState.identity(from:)) else {
            throw MinerToolError.message("Cooling access or settings changed. Refresh before applying. No request was sent.")
        }
        let changes = try requested.liveChanges(from: baseline)
        guard !changes.isEmpty else { throw MinerToolError.message("No cooling changes to apply.") }
        let operation = MinerOperationModel(session: store.session)
        await operation.execute(
            device: device, endpoint: .settings, body: try JSONEncoder().encode(JSONValue.object(changes)),
            query: [], isDemo: store.isDemo,
            validatePreflight: { fresh in
                guard MinerInlineActionState.identity(from: fresh) == identity,
                      MinerCoolingPreviewDraft(info: fresh) == baseline else {
                    throw MinerToolError.message("Cooling settings changed on the miner. Refresh and review again. No write was sent.")
                }
            },
            writeAuthorized: {
                canWriteLiveCooling && MinerCoolingPreviewDraft(info: info) == baseline
                    && info.flatMap(MinerInlineActionState.identity(from:)) == identity
            }
        )
        if let error = operation.error { throw MinerToolError.message("Cooling change not verified: \(error)") }
        guard await store.refreshAfterWrite(for: device), let refreshed = info else {
            throw MinerToolError.message("Request accepted, but a fresh reading was unavailable. Refresh before trying again.")
        }
        let readback = MinerCoolingPreviewDraft(info: refreshed)
        guard readback.automatic == requested.automatic,
              requested.activeFields.allSatisfy({ readback[$0] == requested[$0] }) else {
            throw MinerToolError.message("Request accepted, but the miner did not report the requested cooling settings. Check the miner before trying again.")
        }
        return readback
    }

    private var reviewedCoolingPage: some View {
        let temperatureReading = info?.raw["temp"]?.intValue.map { "\($0) °C" } ?? "Not reported"
        let fanSpeedReading = info?.raw["fanspeed"]?.intValue.map { "\($0) %" } ?? "Not reported"
        return proposalPage("Cooling", subtitle: "Thermal and fan controls.") {
            settingsHubCard {
                HStack(alignment: .center, spacing: 8) {
                    settingsHubHeader(
                        "Current readings",
                        subtitle: "Last values reported by this miner.",
                        symbol: "thermometer"
                    )
                    if !dynamicTypeSize.isAccessibilitySize {
                        Spacer(minLength: 4)
                        FleetAnimatedArt(
                            .minerCooling,
                            size: CGSize(width: 72, height: 72),
                            accessibilityIdentifier: "settings.cooling.artwork"
                        )
                    }
                }
                Divider().overlay(FleetTheme.separator)
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        coolingReading(
                            temperatureReading,
                            label: "Chip temperature",
                            accessibilityIdentifier: "settings.cooling.temperatureReading"
                        )
                        Divider().overlay(FleetTheme.separator)
                        coolingReading(
                            fanSpeedReading,
                            label: "Fan speed",
                            accessibilityIdentifier: "settings.cooling.fanSpeedReading"
                        )
                    }
                } else {
                    HStack {
                        coolingReading(
                            temperatureReading,
                            label: "Chip temperature",
                            accessibilityIdentifier: "settings.cooling.temperatureReading"
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Divider().frame(height: 42).overlay(FleetTheme.separator)

                        coolingReading(
                            fanSpeedReading,
                            label: "Fan speed",
                            accessibilityIdentifier: "settings.cooling.fanSpeedReading"
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .fleetStaggeredEntrance(index: 0, reduceMotion: reduceMotion)

            settingsHubCard {
                settingsHubHeader("Fan control", subtitle: "Automatic fan, speed and temperature.", symbol: "fan")
                Divider().overlay(FleetTheme.separator)
                HStack {
                    Text("Automatic fan control").foregroundStyle(FleetTheme.ink)
                    Spacer()
                    Toggle("Automatic fan control", isOn: $autoFan).labelsHidden().tint(FleetTheme.positive)
                }
                .fleetFont(.subheadline)
                .padding(.vertical, 7)
                .overlay(alignment: .bottom) { Divider().overlay(FleetTheme.separator) }
                fieldNote("autofanspeed", label: "automatic fan control")

                if autoFan {
                    HStack {
                        Text("Temperature target").foregroundStyle(FleetTheme.ink)
                        Spacer()
                        TextField("Temperature target (°C)", text: $temperatureTarget)
                            .focused(editingFocus, equals: .temperature)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .frame(width: regularNumericFieldWidth)
                            .id(EditingField.temperature)
                        Text("°C").foregroundStyle(FleetTheme.secondary)
                    }
                    .fleetFont(.subheadline)
                    .padding(.vertical, 7)
                    fieldNote("temptarget", label: "the temperature target")
                } else {
                    HStack {
                        Text("Manual fan speed").foregroundStyle(FleetTheme.ink)
                        Spacer()
                        TextField("Manual fan speed (%)", text: $fanSpeed)
                            .focused(editingFocus, equals: .fanSpeed)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .frame(width: compactNumericFieldWidth)
                            .id(EditingField.fanSpeed)
                        Text("%").foregroundStyle(FleetTheme.secondary)
                    }
                    .fleetFont(.subheadline)
                    .padding(.vertical, 7)
                    fieldNote("manualFanSpeed", label: "the manual fan speed")
                }

                Text(
                    ("Current audited firmware accepts a 35–66 °C target and 0–100% manual fan input. "
                    + "These are API constraints, not a safety recommendation. Older firmware differs. "
                        + "Low fan speed or a high target can cause overheating. "
                            + "Existing thermal protection settings are left untouched.")
                )
                .fleetFont(.caption).foregroundStyle(FleetTheme.warning)
                proposalReviewButton("Review cooling change") {
                    do {
                        show(
                            .settings,
                            json: try MinerTuningDraft.coolingPayload(
                                automatic: autoFan,
                                manualSpeed: fanSpeed,
                                target: temperatureTarget
                            )
                        )
                    } catch { self.error = error.localizedDescription }
                }
                Text("Review and confirm before sending to your miner.")
                    .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .fleetStaggeredEntrance(index: 1, reduceMotion: reduceMotion)

            if autoFan {
                settingsHubCard {
                    settingsHubHeader(
                        "Minimum fan speed",
                        subtitle: "Lowest speed automatic control may request.",
                        symbol: "wind"
                    )
                    Divider().overlay(FleetTheme.separator)
                    HStack {
                        Text("Minimum fan speed").foregroundStyle(FleetTheme.ink)
                        Spacer()
                        TextField("Minimum fan speed (%)", text: $minFanSpeed)
                            .focused(editingFocus, equals: .minFanSpeed)
                            .id(EditingField.minFanSpeed)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .frame(width: compactNumericFieldWidth)
                        Text("%").foregroundStyle(FleetTheme.secondary)
                    }
                    .fleetFont(.subheadline)
                    .padding(.vertical, 7)
                    fieldNote("minFanSpeed", label: "the minimum fan speed")
                    Text(
                        ("Automatic control only. Audited firmware accepts 0–99% and uses this as the lowest speed "
                        + "its temperature controller may request while automatic control is on. "
                            + "Overheat, paused, no-pool and startup states use their own fixed speeds instead. "
                            + "0 permits a fully stopped fan. "
                                + "This is a firmware input bound, not a safe airflow recommendation for your board.")
                    )
                    .fleetFont(.caption).foregroundStyle(FleetTheme.warning)
                    proposalReviewButton("Review minimum fan speed") {
                        do { show(.settings, json: try MinerTuningDraft.minimumFanSpeedPayload(minFanSpeed)) } catch {
                            self.error = error.localizedDescription
                        }
                    }
                }
                .fleetStaggeredEntrance(index: 2, reduceMotion: reduceMotion)
            }
        }
    }

    private func coolingReading(
        _ value: String,
        label: String,
        accessibilityIdentifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .fleetFont(.title3, weight: .bold)
                .foregroundStyle(FleetTheme.ink)
                .fleetNumericUpdate(value)
                .accessibilityIdentifier(accessibilityIdentifier)
            Text(label)
                .fleetFont(.caption)
                .foregroundStyle(FleetTheme.secondary)
        }
    }

    var displayPage: some View {
        proposalPage("Display", subtitle: "Rotation, colors and screen timeout.", showsSaveFeedback: !showsDisplayFeedbackByButton) {
            settingsHubCard {
                settingsHubHeader(
                    "Screen rotation",
                    subtitle: "Orientation of the miner's built-in screen.",
                    symbol: "display"
                )
                Divider().overlay(FleetTheme.separator)
                HStack {
                    Text("Screen rotation").foregroundStyle(FleetTheme.ink)
                    Spacer()
                    Picker("Screen rotation", selection: $screenRotation) {
                        Text("Choose rotation").tag(Optional<Int>.none)
                        ForEach([0, 90, 180, 270], id: \.self) { value in Text("\(value)°").tag(Optional(value)) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .disabled(isSaving || isRestartingDisplay)
                }
                .fleetFont(.subheadline)
                .padding(.vertical, 7)
                fieldNote("rotation", label: "screen rotation")
                displaySaveButton("Save rotation", setting: .rotation) {
                    try MinerTuningDraft.rotationPayload(screenRotation)
                }
            }
            .fleetStaggeredEntrance(index: 0, reduceMotion: reduceMotion)

            settingsHubCard {
                settingsHubHeader(
                    "Screen colors",
                    subtitle: "Invert the display for readability.",
                    symbol: "circle.lefthalf.filled"
                )
                Divider().overlay(FleetTheme.separator)
                HStack {
                    Text("Invert screen colors").foregroundStyle(FleetTheme.ink)
                    Spacer()
                    Toggle("Invert screen colors", isOn: $screenInverted).labelsHidden().tint(FleetTheme.positive)
                        .disabled(isSaving || isRestartingDisplay)
                        .accessibilityIdentifier("settings.display.inversion")
                }
                .fleetFont(.subheadline)
                .padding(.vertical, 7)
                fieldNote("invertscreen", label: "inverted screen colors")
                displaySaveButton("Save screen colors", setting: .colors) {
                    MinerTuningDraft.inversionPayload(screenInverted)
                }
            }
            .fleetStaggeredEntrance(index: 1, reduceMotion: reduceMotion)

            settingsHubCard {
                settingsHubHeader(
                    "Display timeout",
                    subtitle: "Idle behaviour of the miner's screen.",
                    symbol: "clock"
                )
                Divider().overlay(FleetTheme.separator)
                HStack {
                    Text("Display timeout").foregroundStyle(FleetTheme.ink)
                    Spacer()
                    TextField("Display timeout (minutes)", text: $displayTimeout)
                        .focused(editingFocus, equals: .displayTimeout)
                        .submitLabel(.done)
                        .onSubmit { editingFocus.wrappedValue = nil }
                        .accessibilityIdentifier("settings.display.timeout")
                        .id(EditingField.displayTimeout)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numbersAndPunctuation)
                        .frame(width: regularNumericFieldWidth)
                        .disabled(isSaving || isRestartingDisplay)
                    Text("min").foregroundStyle(FleetTheme.secondary)
                }
                .fleetFont(.subheadline)
                .padding(.vertical, 7)
                fieldNote("displayTimeout", label: "the display timeout")
                Text(
                    ("−1 keeps the display on, 0 turns it off, and positive values set an idle timeout in minutes. "
                    + "Save sends only this display setting. Hardware and firmware support vary.")
                )
                .fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
                displaySaveButton("Save display timeout", setting: .timeout) {
                    try MinerTuningDraft.displayTimeoutPayload(displayTimeout)
                }
            }
            .fleetStaggeredEntrance(index: 2, reduceMotion: reduceMotion)
        }
    }
}
