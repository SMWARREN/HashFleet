import SwiftUI
import HashFleetCore

extension MinerSettingsView {
    /// Existing editors own edit state in both the design fixture and phone review build.
    func compactSettingsHub(_ availability: MinerNumberFirstAvailability) -> some View {
        let mode = store.preferences.dashboardMode
        let categories = availability.settingsCategories(usesEssentialsPools: usesEssentialsPools)
        let canRestart = availability.quickActions.contains(.restart) && !liveRestart.unsupported.contains(.restart)

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if store.isDemo {
                    Label("Demo only · No miner connected", systemImage: "sparkles")
                        .fleetFont(.footnote, weight: .semibold)
                        .foregroundStyle(FleetTheme.accent)
                } else if offlineReadOnly {
                    MinerOfflineSettingsNotice(snapshot: store.snapshot(for: device.id))
                }
                if !categories.isEmpty || canRestart || liveRestart.receipt != nil || showsAvalonControls(availability)
                    || showsFirmwareExtras(availability) {
                    compactHubGroup("Controls") {
                        if showsAvalonControls(availability) {
                            compactHubLink("Avalon controls", subtitle: avalonControlsSubtitle, icon: "slider.horizontal.3",
                                           id: "settings.preview.avalon") {
                                MinerAvalonControlsPage(device: device, store: store)
                            }
                            if !categories.isEmpty || canRestart || showsFirmwareExtras(availability) { compactHubDivider }
                        }
                        if showsFirmwareExtras(availability) {
                            compactHubLink("Firmware settings", subtitle: firmwareExtrasSubtitle, icon: "cpu",
                                           id: "settings.preview.firmwareExtras") {
                                MinerFirmwareExtrasPage(device: device, store: store)
                            }
                            if !categories.isEmpty || canRestart { compactHubDivider }
                        }
                        ForEach(categories) { category in
                            compactCategory(category)
                            if category != categories.last || canRestart { compactHubDivider }
                        }
                        if canRestart {
                            if mode == .essentials {
                                compactPreviewRestart
                            } else {
                                compactHubLink("Restart device", subtitle: "Review before restarting", icon: "arrow.clockwise",
                                               id: "settings.preview.restart") {
                                    MinerEndpointView(device: device, store: store, endpoint: .restart, insights: insights)
                                }
                            }
                        }
                        if !store.isDemo && mode == .essentials {
                            MinerInlineActionFeedback(state: liveRestart)
                                .padding(.leading, 36)
                                .accessibilityIdentifier("settings.preview.restartResult")
                        }
                    }
                } else {
                    Label("No editable settings available", systemImage: "lock")
                        .fleetFont(.subheadline).foregroundStyle(FleetTheme.secondary)
                }

                if mode == .full, availability.rawAPI {
                    compactHubGroup("Tools") {
                        compactHubLink("Diagnostics", subtitle: "Readings reported by this miner", icon: "stethoscope",
                                       id: "settings.preview.diagnostics") {
                            compactToolPage("Diagnostics") { reportedStateCard }
                        }
                        compactHubDivider
                        compactHubLink("Check compatibility", subtitle: "See what the firmware reports", icon: "checkmark.seal",
                                       id: "settings.preview.compatibility") {
                            MinerCompatibilityView(device: device, store: store, insights: insights)
                        }
                        if let notice = compactFirmwareNotice(availability),
                           let latest = notice.latestVersion {
                            compactHubDivider
                            compactHubLink("Firmware updates", subtitle: "Installed and available versions",
                                           icon: "arrow.down.circle", id: "settings.preview.firmware") {
                                compactToolPage("Firmware updates") {
                                    settingsHubCard {
                                        LabeledContent("Installed", value: notice.currentVersion)
                                        LabeledContent("Available", value: latest)
                                        if store.isDemo {
                                            Text("Demo release example · no install")
                                                .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .fleetPageContainer(compactMaxWidth: FleetLayout.readableWidth)
        }
        .accessibilityIdentifier("settings.preview.hub")
    }

    private func compactFirmwareNotice(_ availability: MinerNumberFirstAvailability) -> FirmwareUpdateNotice? {
        if store.isDemo { return availability.firmwareUpdate(NumberFirstPreview.minerFirmwareNotice) }
        guard let notice = store.firmwareUpdates.notice(for: device.id),
              store.firmwareUpdates.shouldShow(notice, for: device.id) else { return nil }
        return notice
    }

    @ViewBuilder private func compactCategory(_ category: MinerSettingsCategory) -> some View {
        switch category {
        case .general:
            compactHubLink("General", subtitle: "Hostname and on-device history", icon: "gearshape",
                           id: "settings.preview.general") { categoryDestination(.general) }
        case .pools:
            compactHubLink("Pools", subtitle: "Primary and fallback connections", icon: "network",
                           id: "settings.preview.pools") { categoryDestination(.pools) }
        case .display:
            compactHubLink("Display", subtitle: "Rotation, colors and screen timeout", icon: "display",
                           id: "settings.preview.display") {
                // The active navigation destination must own the save alert and its draft.
                MinerSettingsView(device: device, store: store, insights: insights, initialCategory: .display)
            }
        case .cooling:
            compactHubLink("Cooling", subtitle: "Fan mode, speed and temperature", icon: "fan",
                           id: "settings.preview.cooling") { categoryDestination(.cooling) }
        case .tuning:
            compactHubLink("Frequency & voltage", subtitle: "Board-wide tuning", icon: "gauge.with.dots.needle.67percent",
                           id: "settings.preview.tuning") { categoryDestination(.tuning) }
        case .advanced:
            EmptyView()
        }
    }

    private func compactHubGroup<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .fleetFont(.headline, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 5)
            rows()
        }
        .foregroundStyle(FleetTheme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fleetCard(padding: 12, border: .clear, cornerRadius: 16)
    }

    private var compactHubDivider: some View {
        Divider().overlay(FleetTheme.separator).padding(.leading, 36).accessibilityHidden(true)
    }

    private var compactPreviewRestart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                guard usesCompactSettingsHubPreview, store.preferences.dashboardMode == .essentials,
                      let info, NumberFirstPreview.minerAvailability(info, device: device, store: store)
                        .quickActions.contains(.restart) else { return }
                if store.isDemo {
                    previewRestartApplied = true
                    MinerQuickActionPreviewResult.announce(.restart)
                } else {
                    Task { await liveRestart.send(.restart, device: device, store: store) }
                }
            } label: {
                compactHubRow("Restart device", subtitle: store.isDemo ? "Simulate a restart" : "Restarts now and briefly stops mining",
                              icon: "arrow.clockwise", showsChevron: false)
            }
            .buttonStyle(.plain)
            .disabled(!store.isDemo && liveRestart.isSending)
            .accessibilityLabel("Restart device")
            .accessibilityHint(store.isDemo ? "Simulates a restart without contacting a miner." : "Sends restart now.")
            .accessibilityIdentifier("settings.preview.restart")
            if previewRestartApplied {
                MinerQuickActionPreviewResult(action: .restart)
                    .padding(.leading, 36)
                    .accessibilityIdentifier("settings.preview.restartResult")
            }
        }
    }

    private func compactHubLink<Destination: View>(
        _ title: String, subtitle: String, icon: String, id: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            compactHubRow(title, subtitle: subtitle, icon: icon, showsChevron: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityIdentifier(id)
    }

    private func compactHubRow(_ title: String, subtitle: String, icon: String, showsChevron: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .fleetFont(.subheadline, weight: .semibold)
                .foregroundStyle(FleetTheme.accent)
                .frame(width: 26, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fleetFont(.subheadline, weight: .semibold).foregroundStyle(FleetTheme.ink)
                Text(subtitle).fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .fleetFont(.caption2, weight: .semibold)
                    .foregroundStyle(FleetTheme.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func compactToolPage<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content().fleetPageContainer(compactMaxWidth: FleetLayout.readableWidth)
        }
        .background(FleetTheme.canvas)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension MinerSettingsView {
    /// Canaan Avalon miners (port 4028) get their own controls page: work mode, fan, frequency,
    /// LED locator and hash power, all from Canaan's API manual and MinerWatch's driver.
    func showsAvalonControls(_ availability: MinerNumberFirstAvailability) -> Bool {
        ["canaan", "canaannano3"].contains(availability.driverCapabilities.family)
            && availability.rawAPI && !availability.driverCapabilities.isReadOnly
    }

    func showsFirmwareExtras(_ availability: MinerNumberFirstAvailability) -> Bool {
        availability.rawAPI && !availability.driverCapabilities.isReadOnly
            && !MinerFirmwareExtras.controls(for: availability.driverCapabilities.family).isEmpty
    }

    var firmwareExtrasSubtitle: String {
        MinerFirmwareExtras.controls(for: device.firmwareFamily ?? "bitaxe").prefix(3).map(\.title).joined(separator: ", ")
    }

    var avalonControlsSubtitle: String {
        device.firmwareFamily == "canaannano3" ? "Work level" : "Work mode, fan, frequency, LED, hash power"
    }
}
