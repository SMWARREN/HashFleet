import SwiftUI
import HashFleetCore

struct FleetPreferencesView: View {
    @Bindable var preferences: FleetPreferences
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    var store: FleetStore?
    var onPreviewCelebration: ((FleetCelebration.Kind) -> Void)?
    @State private var databaseSize: Int64 = 0
    @State private var showClearConfirmation = false
    @State private var isClearingTelemetry = false
    @State private var telemetryError: String?
    @State private var menuBarVisibility: FleetMenuBarVisibilityMode
    @State private var menuBarStatusMessage: String?

    init(
        preferences: FleetPreferences,
        store: FleetStore? = nil,
        onPreviewCelebration: ((FleetCelebration.Kind) -> Void)? = nil
    ) {
        self.preferences = preferences
        self.store = store
        self.onPreviewCelebration = onPreviewCelebration
        let menuStorage = store?.menuBarPreferenceStorage ?? .shared
        _menuBarVisibility = State(initialValue: menuStorage.load())
    }

    private var menuBarStorage: FleetMenuBarPreferenceStorage {
        store?.menuBarPreferenceStorage ?? .shared
    }

    var body: some View {
        FleetSettingsForm {
            orderSection
            appearanceSection
            monitoringSection
            if FleetLayout.isMac {
                macMenuBarSection
            }
            telemetrySection
            FleetNotificationSettingsSections(
                preferences: preferences,
                onPreviewCelebration: onPreviewCelebration
            )
            FleetSettingsSection("Public network & pool data") {
                FleetSettingsRow {
                    Toggle("Show external data", isOn: $preferences.externalDataEnabled)
                }
                    .accessibilityIdentifier("preferences.externalData")
                Text(
                    "Free Bitcoin and Bitcoin Cash network data appears on the home screen while the app is open. "
                        + "Configured CKPool and SoloFury slots that are recognized also fetch public pool "
                        + "and account statistics, "
                        + "including fallback slots. Providers see your internet IP address and, for account statistics, "
                        + "the configured payout address. No passwords or local miner addresses are sent. "
                        + "Turn this off to keep Hash Fleet local-only."
                )
                .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
            }
            .listRowBackground(FleetTheme.surface)
        }
        .fleetFont(.body)
        .scrollContentBackground(.hidden)
        .background(FleetTheme.canvas)
        .tint(FleetTheme.accent)
        .fleetAppNavigation { $0.navigationTitle("Preferences") }
        // The board uses the compact inline header on every sub-page rather than an iOS large title.
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard FleetLayout.isMac, phase == .active else { return }
            menuBarVisibility = menuBarStorage.load()
        }
        .task(id: scenePhase) {
            guard FleetLayout.isMac else { return }
            while !Task.isCancelled {
                if scenePhase == .active {
                    menuBarVisibility = menuBarStorage.load()
                }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }

    private var orderSection: some View {
        FleetSettingsSection {
            FleetSettingsRow {
                FleetSettingsPicker("Sort by", valueTitle: preferences.sort.title, selection: $preferences.sort) {
                    ForEach(FleetPreferences.SortOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            }
            .accessibilityIdentifier("preferences.sortOption")

            FleetSettingsRow(showsSeparator: false) {
                FleetSettingsPicker("Direction", valueTitle: preferences.ascending ? "Ascending" : "Descending", selection: $preferences.ascending) {
                    Text("Ascending").tag(true)
                    Text("Descending").tag(false)
                }
            }
            .accessibilityIdentifier("preferences.ascending")
        } header: {
            Text("Miner order")
        } footer: {
            Text(
                "When sorting by a reading or firmware, miners with unavailable values appear last in either direction."
            )
            .fleetFont(.footnote)
            .foregroundStyle(FleetTheme.secondary)
        }
        .listRowBackground(FleetTheme.surface)
    }

    private var appearanceSection: some View {
        FleetSettingsSection {
            FleetSettingsRow {
                FleetSettingsPicker("Color mode", valueTitle: preferences.appearance.title, selection: $preferences.appearance) {
                    ForEach(FleetPreferences.Appearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
            }
            .accessibilityIdentifier("preferences.appearance")
            .fleetTourTarget("guide.appearance")
            FleetSettingsRow(showsSeparator: false) {
                Toggle("Compact miner cards", isOn: $preferences.compactCards)
            }
                .accessibilityIdentifier("preferences.compactCards")
        } header: {
            Text("Appearance")
        } footer: {
            Text(Self.appearanceNote)
                .fleetFont(.footnote)
                .foregroundStyle(FleetTheme.secondary)
        }
        .listRowBackground(FleetTheme.surface)
    }

    private var monitoringSection: some View {
        FleetSettingsSection {
            FleetSettingsRow(showsSeparator: false) {
                Toggle("Realtime miner readings", isOn: $preferences.realtimeMonitoring)
            }
                .accessibilityIdentifier("preferences.realtimeMonitoring")
        } header: {
            Text("Live readings")
        } footer: {
            Text(
                "A read-only live connection while Fleet is open, with HTTP fallback for miners that cannot stream. "
                    + "When off, opening Fleet or pulling to refresh still fetches readings. "
                    + "This does not enable continuous background monitoring or change miner hardware."
            )
            .fleetFont(.footnote)
            .foregroundStyle(FleetTheme.secondary)
        }
        .listRowBackground(FleetTheme.surface)
    }

    private var macMenuBarSection: some View {
        FleetSettingsSection {
            FleetSettingsRow(showsSeparator: false) {
                Toggle("Show fleet status", isOn: Binding(
                    get: { menuBarVisibility == .always },
                    set: { setMenuBarVisibility($0 ? .always : .hidden) }
                ))
            }
            .accessibilityIdentifier("preferences.macMenuBarVisibility")
            if let menuBarStatusMessage {
                Text(menuBarStatusMessage)
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.secondary)
                    .accessibilityIdentifier("preferences.macMenuBarStatus")
            }
        } header: {
            Text("Mac menu bar")
        } footer: {
#if os(macOS)
            Text("The menu bar is part of Hash Fleet. It continues updating after you close the workspace window and stops when you quit Hash Fleet.")
                .fleetFont(.footnote)
                .foregroundStyle(FleetTheme.secondary)
#else
            Text(
                "The read-only fleet summary stays in the Mac menu bar after Hash Fleet closes. "
                    + "Turn this off to hide the system item. The companion never changes miner settings."
            )
#endif
        }
        .listRowBackground(FleetTheme.surface)
    }

    private static var appearanceNote: String {
        #if os(macOS)
        "System follows your Mac's Light or Dark appearance automatically. Compact cards fit more miners on screen. These preferences never change miner settings."
        #else
        "System follows your device's Light or Dark appearance automatically. Home Screen icon variants "
            + "follow \(FleetDeviceCopy.current.systemName) when icon appearance is Automatic. Compact cards "
            + "fit more miners on screen. These preferences never change miner settings."
        #endif
    }

    private func setMenuBarVisibility(_ mode: FleetMenuBarVisibilityMode) {
        menuBarVisibility = mode
        guard menuBarStorage.save(mode) else {
            menuBarStatusMessage = "Hash Fleet could not save the menu-bar preference."
            return
        }
        guard mode.shouldShow else {
            menuBarStatusMessage = "Fleet status is hidden from the Mac menu bar."
            return
        }

#if os(macOS)
        menuBarStatusMessage = mode.shouldShow
            ? "The native Hash Fleet menu bar is enabled. It continues until you quit the app."
            : "Fleet status is hidden from the Mac menu bar."
#else
        Task { @MainActor in
            let accepted = await FleetExternalURL.open(FleetMenuBarLaunch.showURL, using: openURL)
            guard !Task.isCancelled else { return }
            menuBarStatusMessage = accepted
                ? "Fleet status is starting in the Mac menu bar."
                : "The separate Hash Fleet Menu Bar companion is not installed. Install it separately, then try again."
        }
#endif
    }

    private var telemetrySection: some View {
        FleetSettingsSection {
            FleetSettingsRow {
                Toggle("Store telemetry history", isOn: $preferences.telemetryStorageEnabled)
            }
                .accessibilityIdentifier("preferences.telemetryStorageEnabled")

            if preferences.telemetryStorageEnabled {
                FleetSettingsRow {
                    FleetSettingsPicker("Keep data for", valueTitle: preferences.telemetryRetention.title, selection: $preferences.telemetryRetention) {
                        ForEach(FleetPreferences.TelemetryRetention.allCases) { retention in
                            Text(retention.title).tag(retention)
                        }
                    }
                }
                .accessibilityIdentifier("preferences.telemetryRetention")

                HStack {
                    Text("Database size")
                    Spacer()
                    Text(formatBytes(databaseSize))
                        .foregroundStyle(FleetTheme.secondary)
                }
                .frame(minHeight: 44)
                .fleetSettingsRowSeparator()

                FleetSettingsRow(showsSeparator: false) {
                    Button("Clear all telemetry data", role: .destructive) {
                        showClearConfirmation = true
                    }
                }
                .disabled(isClearingTelemetry || store?.isDemo == true)
                .confirmationDialog(
                    "Clear all telemetry data?",
                    isPresented: $showClearConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Clear all data", role: .destructive) {
                        Task { @MainActor in
                            guard !isClearingTelemetry else { return }
                            isClearingTelemetry = true
                            telemetryError = nil
                            defer { isClearingTelemetry = false }
                            if let store {
                                // Full reset: DB plus per-device baselines so tracking restarts fresh.
                                guard await store.clearAllTelemetryAndAchievements() else {
                                    telemetryError = store.persistenceError
                                    return
                                }
                            } else {
                                do { try await MinerTelemetryDatabase.shared.clearAllDataChecked() } catch {
                                    telemetryError = "Unable to clear telemetry: \(error.localizedDescription)"
                                    return
                                }
                            }
                            await updateDatabaseSize()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will delete all stored miner readings, achievements, and history. This cannot be undone.")
                }
                if let telemetryError {
                    Label(telemetryError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(FleetTheme.warning)
                        .accessibilityIdentifier("preferences.telemetryError")
                }
            }
        } header: {
            Text("Telemetry storage")
        } footer: {
            Text(
                "When enabled, all miner readings (hashrate, temperature, power, achievements) are stored in a local database. "
                    + "This lets you view historical charts and mining milestones from previous sessions. "
                    + "Data older than the retention period is automatically deleted. "
                    + "Turn this off to keep telemetry in-memory only."
            )
        }
        .listRowBackground(FleetTheme.surface)
        .task {
            await updateDatabaseSize()
        }
        .onChange(of: preferences.telemetryStorageEnabled) { _, _ in
            Task { await updateDatabaseSize() }
        }
    }

    private func updateDatabaseSize() async {
        databaseSize = await MinerTelemetryDatabase.shared.getDatabaseSize()
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#Preview("Fleet preferences") {
    NavigationStack {
        FleetPreferencesView(
            preferences: FleetPreferences(defaults: UserDefaults(suiteName: "app.hashfleet.preferences-preview")!)
        )
    }
}
