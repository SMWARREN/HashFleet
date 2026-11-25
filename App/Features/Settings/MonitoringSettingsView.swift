import SwiftUI

struct MonitoringSettingsView: View {
    @Environment(\.fleetGuidedEssentials) private var guidedEssentials
    let store: FleetStore
    @Bindable var coordinator: FleetGlanceCoordinator
    /// Only the split workspace root owns a bound path. A Settings page pushed
    /// by presentation binding must retain view-based links above that root.
    var usesWorkspacePath = false
    // Keep the existing pool-demo closure last for trailing-closure call sites.
    var onPreviewCelebration: ((FleetCelebration.Kind) -> Void)?
    var showPoolIconDemo: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fleetStandalonePage) private var standalonePage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var showingFeatureTour = false
    @State var notificationsExpanded = false

    private enum Destination: Hashable {
        case fleet, achievements, temperatureAlerts, powerAlerts, energy, reports, backup, performance
        #if os(iOS)
        case widgets, liveActivity, systemFeatures, appleWatch
        #endif
    }

    var body: some View {
        FleetSettingsList {
            FleetSettingsSection(
                surface: nil,
                contentInsets: EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0),
                listRowInsets: EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0),
                hidesListRowSeparators: true
            ) {
                settingsHero
            }
            FleetSettingsSection {
                FleetSettingsRow(showsSeparator: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dashboard view")
                            .fleetFont(.headline)
                            .accessibilityAddTraits(.isHeader)
                        dashboardViewSelector
                            .fleetTourTarget("guide.dashboardView")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("Essentials keeps the dashboard focused on readings and quick controls. Full View adds comparisons, diagnostics, and API tools.")
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            FleetSettingsSection {
                Button {
                    notificationsExpanded.toggle()
                } label: {
                    HStack {
                        MonitoringDestinationLabel(
                            title: "Notifications and banners",
                            subtitle: "Alert choices and record popups, right here in App settings.",
                            symbol: "bell.badge.fill",
                            tint: .pink
                        )
                        Spacer(minLength: 8)
                        Image(systemName: notificationsExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(FleetTheme.secondary)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(notificationsExpanded ? "Expanded" : "Collapsed")
                .fleetSettingsNavigationRow()
                .accessibilityIdentifier("monitoring.notifications")
                .fleetTourTarget("guide.notificationsEntry")
            }
            if notificationsExpanded {
                FleetNotificationSettingsSections(
                    preferences: store.preferences,
                    onPreviewCelebration: onPreviewCelebration
                )
            }
            FleetSettingsSection {
                settingsLink(.fleet) {
                    MonitoringDestinationLabel(
                        title: "Fleet",
                        subtitle: "Appearance, miner order and live readings.",
                        symbol: "square.grid.2x2",
                        tint: .amber
                    )
                }
                .fleetSettingsNavigationRow()
                .accessibilityIdentifier("monitoring.fleet")
                .fleetTourTarget("guide.preferencesEntry")
            } header: {
                Text("Your fleet").fleetFont(.headline)
            } footer: {
                Text("Looking for miner controls? Open a miner in Fleet.")
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.secondary)
            }
#if os(iOS)
            FleetSettingsSection {
                settingsLink(.widgets) {
                    MonitoringDestinationLabel(
                        title: "Widgets",
                        subtitle: "Saved readings on your Home and Lock Screens.",
                        symbol: "rectangle.3.group",
                        tint: .blue
                    )
                }
                .accessibilityIdentifier("monitoring.widgets")
                settingsLink(.liveActivity) {
                    MonitoringDestinationLabel(
                        title: "Live Activity",
                        subtitle: "A Lock Screen overview while Hash Fleet is open.",
                        symbol: "waveform.path",
                        tint: .green
                    )
                }
                .accessibilityIdentifier("monitoring.liveActivity")
                settingsLink(.appleWatch) {
                    MonitoringDestinationLabel(
                        title: "Apple Watch",
                        subtitle: "Independent readings, even with your phone off.",
                        symbol: "applewatch",
                        tint: .gray
                    )
                }
                .accessibilityIdentifier("monitoring.watch")
                settingsLink(.systemFeatures) {
                    MonitoringDestinationLabel(
                        title: "Shortcuts & Controls",
                        subtitle: "Siri actions and confirmed miner controls.",
                        symbol: "square.stack.3d.up",
                        tint: .indigo
                    )
                }
                .accessibilityIdentifier("monitoring.systemFeatures")
            } header: {
                Text("Across \(FleetDeviceCopy.current.systemName)").fleetFont(.headline)
            }
#endif
            FleetSettingsSection {
                settingsLink(.achievements) {
                    MonitoringDestinationLabel(title: "Mining achievements",
                        subtitle: "Block finds and best share milestones.", symbol: "trophy.fill", tint: .orange)
                }
                .fleetSettingsNavigationRow()
                .accessibilityIdentifier("monitoring.achievements")
                settingsLink(.temperatureAlerts) {
                    MonitoringDestinationLabel(title: "Temperature alerts",
                        subtitle: "Opt-in thresholds for each real miner.", symbol: "thermometer.high", tint: .pink)
                }
                .fleetSettingsNavigationRow()
                .accessibilityIdentifier("monitoring.temperatureAlerts")
                settingsLink(.powerAlerts) {
                    MonitoringDestinationLabel(title: "Power alerts",
                        subtitle: "High-wattage alarms and all-clear notices for each real miner.", symbol: "bolt.trianglebadge.exclamationmark", tint: .orange)
                }
                .fleetSettingsNavigationRow()
                .accessibilityIdentifier("monitoring.powerAlerts")
                settingsLink(.energy) {
                    MonitoringDestinationLabel(title: "Electricity estimates",
                        subtitle: "Project running costs from measured power.", symbol: "bolt.fill", tint: .yellow)
                }
                .fleetSettingsNavigationRow()
                .accessibilityIdentifier("monitoring.energy")
                .fleetTourTarget("guide.energyEntry")
                settingsLink(.reports) {
                    MonitoringDestinationLabel(title: "Fleet reports",
                        subtitle: "Private snapshot reports in PDF or CSV.", symbol: "doc.text.fill", tint: .green)
                }
                .fleetSettingsNavigationRow()
                .accessibilityIdentifier("monitoring.reports")
                .fleetTourTarget("guide.reportEntry")
                settingsLink(.backup) {
                    MonitoringDestinationLabel(title: "Fleet backup",
                        subtitle: "Export addresses and preview a safe restore.", symbol: "arrow.triangle.2.circlepath", tint: .teal)
                }
                .fleetSettingsNavigationRow()
                .accessibilityIdentifier("monitoring.backup")
            } header: {
                Text("Fleet tools").fleetFont(.headline)
            } footer: {
                Text(Self.toolsNote)
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.secondary)
            }
            FleetSettingsSection {
                featureTourEntry
                    .fleetSettingsNavigationRow()
                    .accessibilityIdentifier("monitoring.featureTour")
                Button {
                    store.loadPoolIconDemo()
                    showPoolIconDemo?()
                } label: {
                    MonitoringDestinationLabel(
                        title: "Pool icon demo",
                        subtitle: "Mock miners for every supported pool and coin.",
                        symbol: "sparkles",
                        tint: .pink
                    )
                }
                .buttonStyle(.plain)
                .fleetSettingsNavigationRow()
                .accessibilityIdentifier("monitoring.poolIconDemo")
            } header: {
                Text("Explore").fleetFont(.headline)
            } footer: {
                Text("The feature tour leaves your fleet untouched. The pool icon demo uses mock readings. Exit demo to return to your fleet. Neither changes hardware settings.")
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.secondary)
            }
            FleetSettingsSection {
                settingsLink(.performance) {
                    MonitoringDestinationLabel(
                        title: "Frame pacing",
                        subtitle: "Local callback FPS and timing by screen.",
                        symbol: "speedometer",
                        tint: .gray
                    )
                }
                .fleetSettingsNavigationRow()
                .accessibilityIdentifier("monitoring.performance")
            } header: {
                Text("Diagnostics").fleetFont(.headline)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("App settings page")
        .accessibilityIdentifier("monitoring.settings.page")
        .fleetFont(.body)
        .scrollContentBackground(.hidden)
        .background(FleetTheme.canvas)
        .tint(FleetTheme.accent)
        .fleetAppNavigation { $0.navigationTitle("App settings") }
        // The hero already names the page, so the bar title stays inline rather than repeating a
        // second large "Settings" heading.
        .navigationBarTitleDisplayMode(.inline)
        .fleetAppNavigation { $0.navigationDestination(for: Destination.self, destination: destinationView) }
        .fleetAppNavigation { base in
            base.toolbar {
                if !standalonePage {
                    ToolbarItem(placement: FleetToolbarLocation.trailing) {
                        Button("Done") {
                            dismiss()
                        }
                        .fleetToolbarButton()
                        .accessibilityIdentifier("monitoring.settings.done")
                    }
                    .fleetUnadornedToolbarBackground()
                }
            }
        }
        .fleetPerformanceScreen("App settings")
        .fleetDismissPresentationsOnNavigation { showingFeatureTour = false }
        .fleetPagePresentation(isPresented: $showingFeatureTour, onDismiss: {
            store.preferences.hasSeenFeatureTour = true
        }, content: {
            FleetPageNavigationStack {
                FleetTourView(dontShowAgain: Binding(
                    get: { store.preferences.suppressFeatureTour },
                    set: { store.preferences.suppressFeatureTour = $0 }
                ), onPreviewCelebration: onPreviewCelebration, showsEssentialsWalkthrough: offersEssentialsWalkthrough)
            }
            .fleetPageSheet()
        })
    }

    @ViewBuilder private var dashboardViewSelector: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        layout {
            ForEach(FleetPreferences.DashboardMode.allCases) { mode in
                let selected = mode == store.preferences.dashboardMode
                Button {
                    if !selected {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            store.preferences.dashboardMode = mode
                        }
                    }
                } label: {
                    Text(mode.title)
                        .fleetFont(.subheadline, weight: .semibold)
                        .foregroundStyle(selected ? FleetTheme.ink : FleetTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(FleetTheme.ink.opacity(0.14))
                                    .padding(3)
                            }
                        }
                        .contentShape(Rectangle())
                }
                // In a List each segment must own its touch/click target, not the whole row.
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("settings.dashboardView.\(mode.rawValue)")
            }
        }
        .background(FleetTheme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dashboard view")
        .accessibilityIdentifier("settings.dashboardView")
    }

    @ViewBuilder
    private var featureTourEntry: some View {
        #if os(macOS)
        if usesWorkspacePath {
            NavigationLink(value: FleetTourRoute()) { featureTourLabel }
        } else {
            Button { showingFeatureTour = true } label: { featureTourLabel }
                .buttonStyle(.plain)
        }
        #else
        Button { showingFeatureTour = true } label: { featureTourLabel }
            .buttonStyle(.plain)
        #endif
    }

    private var featureTourLabel: some View {
        MonitoringDestinationLabel(
            title: offersEssentialsWalkthrough ? "Essentials walkthrough" : "Feature tour",
            subtitle: offersEssentialsWalkthrough
                ? "Practice with sample miners. Skip or replay anytime."
                : "A guided walkthrough. Skip or replay anytime.",
            symbol: "sparkles",
            tint: .indigo
        )
    }

    private var offersEssentialsWalkthrough: Bool {
        #if os(iOS)
        NumberFirstPreview.usesLivePhoneLayouts && horizontalSizeClass == .compact
            && !store.isDemo && store.preferences.dashboardMode == .essentials
        #else
        false
        #endif
    }

    /// A value push above a view-backed Settings presentation can replace that
    /// presentation instead of extending it. Keep the original links there and
    /// use path-owned values only for the direct split-workspace root.
    @ViewBuilder
    private func settingsLink<Label: View>(
        _ destination: Destination,
        @ViewBuilder label: () -> Label
    ) -> some View {
        if usesWorkspacePath {
            NavigationLink(value: destination, label: label)
        } else {
            NavigationLink {
                destinationView(destination)
            } label: {
                label()
            }
        }
    }

    /// Register once outside the lazy settings rows. Workspace-owned value
    /// routes pop when the sidebar reselects App settings.
    @ViewBuilder
    private func destinationView(_ destination: Destination) -> some View {
        switch destination {
        case .fleet:
            FleetPreferencesView(
                preferences: store.preferences,
                store: store,
                onPreviewCelebration: onPreviewCelebration
            )
        case .achievements:
            MiningAchievementsView(devices: store.isDemo ? store.savedDevices : store.visibleDevices)
        case .temperatureAlerts:
            FleetTemperatureAlertsView(
                devices: store.isDemo ? store.savedDevices : store.visibleDevices,
                preferences: store.temperatureAlerts,
                isDemo: store.isDemo
            )
        case .powerAlerts:
            FleetPowerAlertsView(
                devices: store.isDemo ? store.savedDevices : store.visibleDevices,
                preferences: store.powerAlerts,
                isDemo: store.isDemo
            )
        case .energy:
            FleetEnergyView(store: store)
        case .reports:
            FleetReportView(store: store)
        case .backup:
            FleetBackupView(store: store)
        case .performance:
            FleetPerformanceSettingsView()
        #if os(iOS)
        case .widgets:
            FleetWidgetSettingsPage(store: store, coordinator: coordinator)
        case .liveActivity:
            FleetLiveActivitySettingsPage(store: store, coordinator: coordinator)
        case .systemFeatures:
            FleetSystemFeaturesView(sharesSavedReadings: coordinator.sharesWithWidgets)
        case .appleWatch:
            FleetWatchSettingsPage(store: store)
        #endif
        }
    }

    private static var toolsNote: String {
        #if os(macOS)
        "Local tools only. Estimates are not metered bills. Alerts require Hash Fleet to be running and never change miner settings."
        #else
        "Local tools only. Estimates are not metered bills. Alerts depend on \(FleetDeviceCopy.current.systemName) and never change miner settings."
        #endif
    }

    /// The proposal opens Settings with the app mark and a one-line orientation. It is decorative
    /// and adds no control, so it is read as a single label by VoiceOver.
    private var settingsHero: some View {
        VStack(spacing: 10) {
            FleetBrandMark(size: FleetLayout.isMac ? 64 : 48)
            Text("Make Fleet yours")
                .fleetFont(.title2, weight: .bold)
                .foregroundStyle(FleetTheme.ink)
            Text("Your readings, your alerts, your way.")
                .fleetFont(.subheadline)
                .foregroundStyle(FleetTheme.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Make Fleet yours. Your readings, your alerts, your way.")
        .accessibilityIdentifier("monitoring.hero")
    }
}

struct MonitoringDestinationLabel: View {
    let title: String
    let subtitle: String
    let symbol: String
    /// Same colored tiles as the sidebar, so a destination looks the same everywhere.
    var tint: FleetSidebarTileTint = .amber

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .fleetFont(.title3, weight: .semibold)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(tint.color.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fleetFont(.headline).foregroundStyle(FleetTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle).fleetFont(.subheadline).foregroundStyle(FleetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview("Settings") {
    let defaults = UserDefaults(suiteName: "app.hashfleet.settings-preview")!
    let store = FleetStore(defaults: defaults)
    let coordinator = FleetGlanceCoordinator(defaults: defaults, isTesting: true)
    return NavigationStack { MonitoringSettingsView(store: store, coordinator: coordinator) }
}

private struct MonitoringSettingsListStyle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
#if os(macOS)
        content.listStyle(.inset)
#else
        content.listStyle(.insetGrouped)
#endif
    }
}
