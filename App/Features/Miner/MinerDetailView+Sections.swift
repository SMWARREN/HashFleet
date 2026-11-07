import SwiftUI
import HashFleetCore

/// Detail-screen sections: control card, quick links, identity rows, fault banner and
/// fleet-management controls. Moved out of MinerDetailView.swift for file/type length;
/// identifiers, wording and behavior are unchanged.
extension MinerDetailView {

    /// Identity and firmware identifiers. Collapsed by default because they are reference values
    /// rather than the live readings, but every row, its wording and its selectable text are the
    /// same ones this screen showed before.
    func identity(_ info: MinerInfo) -> some View {
        let pool = MinerActivePool(info: info)
        // `bestDiff` and `version` are read through the reported-value helper because some firmware
        // sends them unquoted. A missing value stays "Not reported" rather than implying anything.
        return collapsibleCard(
            spec: MinerDetailCardSpec(
                title: "Identity & firmware",
                subtitle: "Active pool, best difficulty, firmware, address",
                symbol: "info.circle",
                id: "detail.identityDisclosure",
                settings: .general,
                settingsID: "detail.identity.settings"
            ),
            expanded: $showsIdentity
        ) {
            VStack(spacing: 11) {
                detailRow(pool.title, value: pool.value)
                detailRow("Best difficulty", value: FleetFormat.difficulty(info.raw["bestDiff"]))
                detailRow(
                    "Firmware",
                    value: MinerCapabilityPresentation.firmwareVersion(info: info)
                        ?? MinerCapabilityPresentation.notReported
                )
                detailRow(
                    "Core voltage",
                    value: FleetFormat.measurement(FleetFormat.sensor(info, keys: "coreVoltage"), unit: "mV")
                )
                detailRow(
                    "Wi-Fi signal",
                    value: FleetFormat.measurement(
                        FleetFormat.sensor(info, keys: "wifiRSSI", "wifiRssi", allowNegative: true),
                        unit: "dBm"
                    )
                )
                FleetSensitiveValue(title: "Address", value: device.address, identifier: "detail.privateAddress")
            }
        }
    }

    /// This miner's own configured pools and their public account statistics. Scoped by `deviceID`,
    /// so opening this section never resolves or queries another miner's payout address.
    ///
    /// No expansion, no card, no lookup. The header owns its accessibility identifier rather than
    /// a DisclosureGroup ancestor, which would overwrite the nested edit link's identifier and
    /// expand the header hit area to include the whole account card.
    var poolsSection: some View {
        collapsibleCard(
            spec: MinerDetailCardSpec(
                title: "Pool status",
                subtitle: "Read-only configured slots and public statistics",
                symbol: "server.rack",
                id: "detail.poolsDisclosure",
                settings: .pools,
                settingsID: "detail.pools.edit"
            ),
            expanded: $showsPools
        ) {
            FleetPoolsCard(fleet: store, deviceID: device.id, marketData: insights?.coinMarkets ?? [:])
        }
    }

    /// The disclosure and settings route are siblings, never controls inside a NavigationLink or
    /// a combined accessibility parent. Settings remain reachable even when readings are folded.
    func collapsibleCard<Content: View>(
        spec: MinerDetailCardSpec,
        expanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        MinerDetailCollapsibleCard(
            spec: spec,
            expanded: expanded,
            device: device,
            store: store,
            insights: insights,
            content: content
        )
    }

    /// Keep the complete reviewed control surface close to the latest miner reading. Opening a
    /// control never sends a command; the destination owns the appropriate review step.
    @ViewBuilder var controlMinerCard: some View {
        if isXMRig {
            xmrigControlLink
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label("CONTROL MINER", systemImage: "slider.horizontal.3")
                        .font(FleetTheme.mono())
                        .foregroundStyle(FleetTheme.accent)
                    Spacer(minLength: 8)
                    Text("Review changes before sending")
                        .fleetFont(.caption2)
                        .foregroundStyle(FleetTheme.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                // The proposal leads with the navigation tiles so Tuning and Cooling stay reachable in
                // the first viewport. The quick endpoint actions keep the same controls just below.
                quickControls
                quickActions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fleetCard(padding: FleetSurfaceSpacing.cardInset)
        }
    }

    var simpleSettingsLink: some View {
        #if os(macOS)
        NavigationLink(value: FleetMinerSettingsRoute(deviceID: currentDevice.id, category: nil)) {
            quickLinkLabel(
                title: "Miner settings",
                subtitle: "All controls and reviewed changes",
                symbol: "slider.horizontal.3"
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("detail.settings")
        .frame(maxWidth: .infinity, alignment: .leading)
        #else
        NavigationLink {
            settingsDestination(nil)
        } label: {
            quickLinkLabel(
                title: "Miner settings",
                subtitle: "All controls and reviewed changes",
                symbol: "slider.horizontal.3"
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("detail.settings")
        .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }

    var xmrigControlLink: some View {
        NavigationLink {
            XMRigControlView(device: currentDevice, store: store)
        } label: {
            toolRow(
                "XMRig control",
                subtitle: "Review pause or resume before sending",
                symbol: "cpu"
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("detail.xmrigControl")
        .accessibilityHint("Opens reviewed pause and resume controls. No command is sent yet.")
    }

    var quickControls: some View {
        FleetMinerDetailGrid(
            maximumColumns: dynamicTypeSize.isAccessibilitySize || usesSingleColumnPhoneControls ? 1 : 2,
            minimumColumnWidth: 160
        ) {
            #if os(macOS)
            AnyView(tuningLink)
            #else
            tuningLink
            #endif
            // Destination-closure NavigationLink inside a custom Layout: keep it behind a
            // type-erased boundary. Copying its opaque type in Layout.callAsFunction crashed
            // in NavigationLink's StateOrBinding copy (Hash Fleet 2026-10-26 18:41).
            AnyView(simpleSettingsLink)
        }
        .buttonStyle(.plain)
    }

    /// The safe, read-only-to-review endpoint actions stay close to the latest reading. They open
    /// the existing endpoint forms; none of these links sends a command by itself.
    var quickActions: some View {
        FleetMinerDetailGrid(maximumColumns: quickActionColumnLimit, minimumColumnWidth: 130, spacing: 8) {
            quickAction(.identify, symbol: "light.beacon.max", id: "detail.quick.identify")
            quickAction(.pause, symbol: "pause", id: "detail.quick.pause")
            quickAction(.resume, symbol: "play", id: "detail.quick.resume")
            quickAction(.restart, symbol: "arrow.clockwise", id: "detail.quick.restart")
        }
        // Do not give this Layout a parent identifier. SwiftUI propagates it to the
        // links and hides their individual identifiers from accessibility clients.
        .accessibilityElement(children: .contain)
    }

    var quickActionColumnLimit: Int {
        if dynamicTypeSize.isAccessibilitySize { return 1 }
        if !FleetLayout.isMac && usesCompactHorizontalLayout { return 2 }
        return 4
    }

    /// Frequency & voltage and Miner settings stay in one readable column on compact phones. The
    /// endpoint actions below use their own two-column layout so common pause/resume controls remain
    /// compact without squeezing the primary settings links.
    var usesSingleColumnPhoneControls: Bool {
        !FleetLayout.isMac && usesCompactHorizontalLayout
    }

    var tuningLink: some View {
        quickLink(
            "Frequency & voltage",
            subtitle: "Clock, core voltage and live readings",
            symbol: "gauge.with.dots.needle.67percent",
            category: .tuning,
            id: "detail.quick.tuning"
        )
    }

    @ViewBuilder
    func quickLink(
        _ title: String,
        subtitle: String,
        symbol: String,
        category: MinerSettingsCategory,
        id: String
    ) -> some View {
        if category == .tuning {
            #if os(macOS)
            // Value route on the Mac fleet stack. Closure links here dropped clicks and left the
            // page blank while NavigationRequestObserver updated repeatedly in one frame.
            NavigationLink(value: FleetMinerSettingsRoute(deviceID: currentDevice.id, category: .tuning)) {
                quickLinkLabel(title: title, subtitle: subtitle, symbol: symbol)
            }
            .fleetPointerHover()
            .accessibilityIdentifier(id)
            .accessibilityHint("Opens the tuning session. Changes still require review and confirmation.")
            .frame(maxWidth: .infinity, alignment: .leading)
            #else
            Button {
                tuningSessionRoute = currentDevice
            } label: {
                quickLinkLabel(title: title, subtitle: subtitle, symbol: symbol)
            }
            .fleetPointerHover()
            .accessibilityIdentifier(id)
            .accessibilityHint("Opens the tuning session. Changes still require review and confirmation.")
            .frame(maxWidth: .infinity, alignment: .leading)
            #endif
        } else {
            NavigationLink {
                settingsDestination(category)
            } label: {
                quickLinkLabel(title: title, subtitle: subtitle, symbol: symbol)
            }
            .fleetPointerHover()
            .accessibilityIdentifier(id)
            .accessibilityHint("Opens the \(title.lowercased()) form. Changes still require review and confirmation.")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func quickLinkLabel(title: String, subtitle: String, symbol: String) -> some View {
        VStack(alignment: .center, spacing: 6) {
            Image(systemName: symbol).fleetFont(.title3).foregroundStyle(FleetTheme.accent)
            Text(title).fleetFont(.subheadline, weight: .semibold).foregroundStyle(FleetTheme.ink)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(subtitle).fleetFont(.caption2).foregroundStyle(FleetTheme.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        }
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity, alignment: .center)
        .multilineTextAlignment(.center)
        .fleetCard(padding: FleetSurfaceSpacing.cardInset)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    func settingsDestination(_ category: MinerSettingsCategory?) -> some View {
        if category == .tuning {
            // Tuning is the unified workspace. Route directly to it from the detail screen so
            // the board-wide controls keep their local state and do not inherit the settings hub's
            // category lifecycle or navigation identity.
            MinerTuningSessionView(device: currentDevice, store: store, insights: insights)
        } else {
            MinerSettingsView(
                device: currentDevice,
                store: store,
                insights: insights,
                initialCategory: category
            )
        }
    }

    func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(FleetTheme.secondary)
            Spacer(minLength: 20)
            if title == "Address" {
                BrowserLink(
                    label: value,
                    rawValue: value,
                    identifier: "detail.address.identity",
                    font: .callout,
                    defaultScheme: "http",
                    alignment: .trailing
                )
                    .frame(maxWidth: 220, alignment: .trailing)
            } else {
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
                    .fleetNumericUpdate(value, reduceMotion: reduceMotion)
            }
        }.fleetFont(.callout)
    }

    var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isXMRig {
                xmrigControlLink
            } else {
                NavigationLink {
                    settingsDestination(nil)
                } label: {
                    toolRow("Settings & pools", subtitle: "Review general, cooling, display and pool changes",
                            symbol: "slider.horizontal.3")
                }
                .accessibilityIdentifier("detail.toolsSettings")
                NavigationLink {
                    MinerCompatibilityView(device: device, store: store, insights: insights)
                } label: {
                    toolRow("Check compatibility", subtitle: "What this firmware actually supports",
                            symbol: "checkmark.seal")
                }
                .accessibilityIdentifier("detail.compatibility")
                if let info {
                    NavigationLink {
                        ScrollView {
                            MinerDiagnosticsView(model: MinerDiagnosticsModel(info: info))
                                .padding(20)
                        }
                        .background(FleetTheme.canvas)
                        .navigationTitle("Diagnostics")
                    } label: {
                        toolRow("Diagnostics", subtitle: "Clocks, cooling, energy and pool state", symbol: "stethoscope")
                    }
                    .accessibilityIdentifier("detail.diagnostics")
                }
                advancedTools
            }
            fleetManagementControls
        }
        .buttonStyle(.plain)
    }

    var advancedTools: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label("Tools & firmware", systemImage: "wrench.and.screwdriver")
                    .fleetFont(.headline)
            }
            .foregroundStyle(FleetTheme.accent)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("detail.advancedSection")
            Text("Inspect the API and explore detailed readings. Commands still require review.")
                .fleetFont(.caption)
                .foregroundStyle(FleetTheme.secondary)
            NavigationLink {
                MinerEndpointCatalogView(device: device, store: store, insights: insights)
            } label: {
                toolRow("Endpoint explorer", subtitle: "Every read, write and firmware operation", symbol: "terminal")
            }
            .accessibilityIdentifier("detail.endpointExplorer")
            NavigationLink {
                MinerEndpointView(device: device, store: store, endpoint: .info, insights: insights)
            } label: {
                toolRow("Raw API", subtitle: "Read the miner's system-info response", symbol: "curlybraces")
            }
            .accessibilityIdentifier("detail.rawAPI")
            NavigationLink {
                MinerCustomJSONRoute(device: device, store: store, insights: insights)
            } label: {
                toolRow("Custom firmware JSON", subtitle: "Inspect and review firmware-specific changes", symbol: "chevron.left.forwardslash.chevron.right")
            }
            .accessibilityIdentifier("detail.customJSON")
            NavigationLink {
                MinerLiveView(device: device, isDemo: store.isDemo, navigationIdentity: navigationIdentity)
            } label: {
                toolRow("Live console", subtitle: "WebSocket telemetry and logs", symbol: "waveform.path.ecg")
            }
            .accessibilityIdentifier("detail.liveConsole")
        }
        .padding(.top, 8)
    }

    var fleetManagementControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Fleet management", systemImage: "person.3")
                .fleetFont(.headline)
                .foregroundStyle(FleetTheme.ink)
            Text("These actions only change Hash Fleet's local list. They never change miner settings.")
                .fleetFont(.caption)
                .foregroundStyle(FleetTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                renameDraft = currentDevice.name
                renameError = nil
                showsRenamePrompt = true
            } label: {
                toolRow("Rename in app", subtitle: "Change the local display name", symbol: "pencil")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("detail.rename")
            .accessibilityHint("Changes this miner's local display name only. Does not change the firmware hostname.")
            .disabled(store.isDemo)
            Button {
                showsRemoveConfirmation = true
            } label: {
                toolRow("Remove from fleet", subtitle: "Remove this miner from the app", symbol: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(FleetTheme.warning)
            .accessibilityIdentifier("detail.removeFromFleet")
            .accessibilityHint("Removes this miner from Hash Fleet only. Does not reset or change the hardware.")
            .disabled(store.isDemo)
            if store.isDemo {
                Label("Demo mode: fleet changes are disabled.", systemImage: "lock.fill")
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
                    .accessibilityIdentifier("detail.demoFleetActionsDisabled")
            }
        }
        .fleetCard(padding: FleetSurfaceSpacing.cardInset)
        .alert("Rename miner", isPresented: $showsRenamePrompt) {
            TextField("Name (optional)", text: $renameDraft)
                .textInputAutocapitalization(.words)
            Button("Save") { renameMiner() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This changes the name shown in Hash Fleet only. Leave it blank to use the automatic model name.")
        }
        .alert("Unable to rename miner", isPresented: Binding(
            get: { renameError != nil },
            set: { if !$0 { renameError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(renameError ?? "The local name could not be saved.")
        }
        .confirmationDialog(
            "Remove \(currentDevice.name) from Hash Fleet?",
            isPresented: $showsRemoveConfirmation,
            titleVisibility: .visible
        ) {
            MinerRemoveFromFleetButton(store: store, device: currentDevice)
            // Adaptive popovers can omit role-cancel buttons. Keep an explicit safe option.
            Button("Keep miner") {}
        } message: {
            Text("This removes the saved miner from the app only. It does not reset, rename, " +
                "or otherwise change the hardware.")
        }
    }

    func renameMiner() {
        do {
            try store.rename(currentDevice, name: renameDraft)
        } catch {
            renameError = error.localizedDescription
        }
    }
}
