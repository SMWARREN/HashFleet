import SwiftUI
import HashFleetCore

public enum MinerSettingsCategory: String, Hashable, CaseIterable, Identifiable, Sendable {
    case general, cooling, display, pools, tuning, advanced
    public var id: String { rawValue }
}

struct MinerSettingsDraft: Hashable {
    let endpoint: MinerEndpoint
    let json: String
    let notice: String?
}

enum MinerPoolPasswordMode: String, CaseIterable, Identifiable {
    case keep
    case replace
    case clear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keep: "Keep current"
        case .replace: "Replace"
        case .clear: "Clear"
        }
    }
}

struct MinerSettingsView: View {
    let device: MinerDevice
    @Bindable var store: FleetStore
    var insights: MiningInsightsStore?
    let initialCategory: MinerSettingsCategory?

    init(
        device: MinerDevice,
        store: FleetStore,
        insights: MiningInsightsStore? = nil,
        initialCategory: MinerSettingsCategory? = nil
    ) {
        self.device = device
        self.store = store
        self.insights = insights
        self.initialCategory = initialCategory
    }

    @State var hostname = ""
    @State var autoFan = true
    @State var fanSpeed = ""
    @State var minFanSpeed = ""
    @State var temperatureTarget = ""
    @State var statsFrequency: Int?
    @State var tuning = MinerTuningDraft()
    @State var screenRotation: Int?
    @State var screenInverted = false
    @State var displayTimeout = ""
    @State var poolMode = "slot"
    @State var slot = 0
    @State var poolURL = ""
    @State var poolPort = "3333"
    @State var poolUser = ""
    @State var poolPassword = ""
    @State var poolPasswordMode: MinerPoolPasswordMode = .keep
    @State var poolReplacementAcknowledged = false
    @State var poolProtocol = "SV1"
    @State var selectedSoloPool: SoloPoolPreset?
    @State var poolPresetMessage: String?
    @State var primarySlot = 0
    @State var secondarySlot = 1
    @State var draft: MinerSettingsDraft?
    @State var quickDraft: MinerSettingsDraft?
    @State var error: String?
    @State var isSaving = false
    @State var saveMessage: String?
    @State var saveAlert: MinerCompletionAlert?
    @State var loaded = false
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) var settingsIconColumnWidth: CGFloat = 22
    @ScaledMetric(relativeTo: .subheadline) var compactNumericFieldWidth: CGFloat = 58
    @ScaledMetric(relativeTo: .subheadline) var regularNumericFieldWidth: CGFloat = 76

    var info: MinerInfo? { store.snapshot(for: device.id)?.info }
    var offlineReadOnly: Bool {
        !store.isDemo && !MinerWriteAvailability.allows(store.snapshot(for: device.id))
    }

    var navigationIdentity: MinerNavigationIdentity {
        let context = MinerMiningContext.resolve(info: info)
        let coin = context.pool?.coin
        return MinerNavigationIdentity(
            deviceName: device.name,
            poolName: context.pool == nil ? nil : context.providerLabel,
            coin: coin,
            market: coin.flatMap { insights?.coinMarkets[$0] }
        )
    }
    /// A successful capability check, used only to describe what the device reported. Absence of a
    /// report never disables a control; it only changes the wording from "not reported" to
    /// "not checked yet".
    var report: MinerCapabilityReport? {
        guard let report = store.capabilities.reports[device.id], report.infoStatus == .supported else { return nil }
        return report
    }

    /// The most recent raw system-info fields available: the capability report when one exists,
    /// otherwise ordinary telemetry. Used to say whether a specific field was actually reported.
    var reportedFields: [String: JSONValue]? {
        if let report, let checkedInfo = report.info,
            report.checkedAt >= (store.snapshot(for: device.id)?.updatedAt ?? .distantPast) {
            return checkedInfo.raw
        }
        return info?.raw
    }

    func reported(_ key: String) -> Bool {
        guard let reportedFields else { return false }
        return reportedFields[key] != nil
    }

    /// A short note for a control whose field the device did not report. Never says "unsupported":
    /// the firmware may still accept the write, and every change is reviewed before sending.
    @ViewBuilder
    func fieldNote(_ key: String, label: String) -> some View {
        if reportedFields == nil {
            Text(
                "No reading for \(label) yet. Run Check compatibility, or enter a value and "
                    + "review the change before sending."
            )
            .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
        } else if !reported(key) {
            Text(MinerCapabilityPresentation.missingFieldNote(label, key: key))
                .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
        }
    }

    /// Keep the category route's concrete type shallow on iOS 26. The Pools page
    /// contains several nested generic forms, and leaving the switch as a
    /// `@ViewBuilder` makes SwiftUI eagerly resolve the full route tree while
    /// updating a navigation destination.
    func categoryDestination(_ category: MinerSettingsCategory) -> AnyView {
        switch category {
        case .general: AnyView(generalPage)
        case .cooling: AnyView(coolingPage)
        case .display: AnyView(displayPage)
        case .pools: AnyView(poolsPage)
        case .tuning: AnyView(tuningPage)
        case .advanced: AnyView(advancedPage)
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: MinerSnapshotFreshness.refreshInterval)) { _ in
            timedContent
        }
    }

    private var timedContent: some View {
        Group {
            if let initialCategory {
                categoryDestination(initialCategory)
            } else {
                AnyView(settingsHubContent)
            }
        }
            .navigationTitle("Miner settings")
            .fleetPerformanceScreen("Miner settings")
            .navigationBarTitleDisplayMode(.inline)
            .background(FleetTheme.canvas).tint(FleetTheme.accent)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    MinerNavigationTitle(pageTitle: "Miner settings")
                }
            }
            .environment(\.minerNavigationIdentity, navigationIdentity)
            .onAppear {
                load()
            }
            .navigationDestination(item: $quickDraft) { request in AnyView(draftDestination(request)) }
            .alert(item: $saveAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onChange(of: info) { _, _ in if !loaded { load() } }
            .onChange(of: offlineReadOnly) { wasOffline, isOffline in
                if wasOffline && !isOffline {
                    loaded = false
                    load()
                }
            }
            .onChange(of: [poolURL, poolPort, poolUser, poolPassword, poolProtocol]) { _, _ in
                poolReplacementAcknowledged = false
            }
            .onChange(of: poolPasswordMode) { _, _ in poolReplacementAcknowledged = false }
    }

    /// The redesigned page header: brand mark, miner identity and its coin.
    /// Native navigation (and its Back button) stays in place above it.
    var minerIdentityHeader: some View {
        HStack(spacing: 12) {
            FleetBrandMark(size: FleetLayout.isMac ? 52 : 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).fleetFont(.headline, weight: .semibold).foregroundStyle(FleetTheme.ink)
                Text(device.address).fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
            }
            Spacer()
            CoinGeckoIcon(coin: navigationIdentity.coin ?? .btc, fallbackTicker: "BTC", size: 24)
        }
        .accessibilityElement(children: .combine)
    }

    /// Large page heading used by the redesigned settings pages. The native
    /// inline navigation title stays for Back, VoiceOver and the page capture tests.
    func pageTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .fleetFont(.largeTitle, weight: .bold, design: .rounded)
                .foregroundStyle(FleetTheme.ink)
            Text(subtitle)
                .fleetFont(.subheadline)
                .foregroundStyle(FleetTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var settingsHubContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                minerIdentityHeader

                if store.isDemo {
                    FleetStatusBadge(title: "DEMO · READ ONLY", color: FleetTheme.accent)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                pageTitle(
                    "Miner controls",
                    subtitle: "Every setting is available here, with review matched to the risk"
                )
                Text(
                    "Use the category that matches the task. Nothing is sent while you edit, and every request "
                        + "shows its target and payload before a change is confirmed."
                )
                .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)

                if offlineReadOnly { MinerOfflineSettingsNotice(snapshot: store.snapshot(for: device.id)) }
                if store.isDemo {
                    Label("Demo settings are previews only", systemImage: "lock.fill")
                        .fleetFont(.footnote).foregroundStyle(FleetTheme.secondary)
                }
                if let error { Text(error).fleetFont(.footnote).foregroundStyle(FleetTheme.warning) }
                quickChangesCard
                controlsCard
                reportedStateCard
                compatibilityCard
            }
            .fleetPageContainer(compactMaxWidth: FleetLayout.readableWidth)
        }
        .scrollIndicators(.hidden)
    }

}

enum MinerSettingsReference {
    static let fields = """
        Pool routing
        useFallbackStratum: number
        primaryPoolIndex, secondaryPoolIndex: integer
        pools: array of Pool objects

        Primary pool
        stratumURL, stratumUser, stratumPassword: string
        stratumPort: integer 1…65535
        stratumProtocol: SV1 | SV2
        stratumV2ChannelType: standard | extended
        stratumV2AuthorityPubkey: base58 string (≤52)

        Fallback pool
        fallbackStratumURL, fallbackStratumUser, fallbackStratumPassword: string
        fallbackStratumPort: integer 1…65535
        fallbackStratumProtocol: SV1 | SV2
        fallbackStratumV2ChannelType: standard | extended
        fallbackStratumV2AuthorityPubkey: base58 string (≤52)

        Network
        ssid: string 1…32
        wifiPass: string 8…63
        hostname: letters, numbers and hyphens

        Hardware / cooling (high risk)
        coreVoltage: integer millivolts 1…65535 (storage bounds, not a safe range)
        frequency: decimal MHz 1…65535 in audited master (legacy schema requires integer)
        Thermal protection flags are intentionally excluded from native tuning.
        autofanspeed: 0 | 1
        manualFanSpeed: integer 0…100
        temptarget: integer °C 35…66 in audited master (local schema incorrectly says 0…100)

        Display / statistics
        rotation: integer 0/90/180/270 in audited master (schema enum 0/1 is incorrect)
        invertscreen: 0 | 1
        useCustomWWW: 0 | 1
        displayTimeout: integer minutes −1…65535 in audited master (legacy schema differs)
        statsFrequency: integer seconds ≥0

        Nested Pool fields
        id: slot 0…7
        stratumURL, stratumUser, stratumPassword: string
        stratumPort: integer 1…65535
        stratumProtocol: SV1 | SV2
        stratumSuggestedDifficulty: number
        stratumExtranonceSubscribe: boolean
        stratumTLS: integer 0 | 1 | 2
        stratumCert: string
        stratumDecodeCoinbase: boolean
        stratumV2ChannelType: standard | extended
        stratumV2AuthorityPubkey: base58 string
        stratumV2RequireAuth: boolean

        Additional firmware-specific PATCH fields are allowed by the schema. Preserve exact case and types.
        Do not assume the running firmware accepts every documented field.
        """
}

#Preview("Miner settings · demo") {
    let store = FleetStore(defaults: UserDefaults(suiteName: "app.hashfleet.miner-settings-preview")!)
    store.loadDemo()
    return NavigationStack {
        MinerSettingsView(device: store.devices[0], store: store)
    }
    .preferredColorScheme(.dark)
}

#Preview("Miner general · proposal") {
    let store = FleetStore(defaults: UserDefaults(suiteName: "app.hashfleet.miner-general-preview")!)
    store.loadDemo()
    return NavigationStack {
        MinerSettingsView(device: store.devices[0], store: store, initialCategory: .general)
    }
    .preferredColorScheme(.dark)
}

#Preview("Miner cooling · proposal") {
    let store = FleetStore(defaults: UserDefaults(suiteName: "app.hashfleet.miner-cooling-preview")!)
    store.loadDemo()
    return NavigationStack {
        MinerSettingsView(device: store.devices[0], store: store, initialCategory: .cooling)
    }
    .preferredColorScheme(.dark)
}

#Preview("Miner display · proposal") {
    let store = FleetStore(defaults: UserDefaults(suiteName: "app.hashfleet.miner-display-preview")!)
    store.loadDemo()
    return NavigationStack {
        MinerSettingsView(device: store.devices[0], store: store, initialCategory: .display)
    }
    .preferredColorScheme(.dark)
}
