import SwiftUI
import HashFleetCore

/// Presentation evidence, not authorization. A reachable Info endpoint and valid readings do
/// not establish that the miner also permits settings or supports firmware updates.
struct MinerNumberFirstAvailability {
    let info: MinerInfo
    let infoStatus: MinerProbeStatus
    let settingsStatus: MinerProbeStatus
    let firmwareStatus: MinerProbeStatus
    var actionStatuses: [MinerDetailQuickAction: MinerProbeStatus] = [:]
    var hasFreshLiveFields = false
    var liveActionCandidates: Set<MinerDetailQuickAction> = []
    var driverCapabilities: MinerDriverCapabilities = .forFamily("bitaxe")

    var canEditSettings: Bool {
        !driverCapabilities.isReadOnly && rawAPI && (settingsStatus.isSupported || hasFreshLiveFields)
    }

    var quickActions: [MinerDetailQuickAction] {
        guard rawAPI else { return [] }
        return MinerDetailQuickAction.allCases.filter {
            actionStatuses[$0] == .supported || liveActionCandidates.contains($0)
        }
    }

    var cooling: Bool {
        guard canEditSettings, driverCapabilities.canSetFan,
              let automatic = info.raw["autofanspeed"]?.boolValue else { return false }
        return automatic
            ? FleetFormat.sensor(info, keys: "temptarget").map { $0 > 0 } == true
            : FleetFormat.sensor(info, keys: "manualFanSpeed").map { $0 <= 100 } == true
    }

    var tuning: Bool {
        canEditSettings
            && driverCapabilities.canSetFrequency
            && driverCapabilities.canSetVoltage
            && (FleetFormat.sensor(info, keys: "frequency") ?? 0) > 0
            && (FleetFormat.sensor(info, keys: "coreVoltage") ?? 0) > 0
    }

    var rawAPI: Bool {
        infoStatus == .supported && MinerShapeValidator.isValidInfoShape(.object(info.raw))
    }

    func settingsCategories(usesEssentialsPools: Bool = false) -> [MinerSettingsCategory] {
        guard canEditSettings else { return [] }
        let raw = info.raw
        var categories: [MinerSettingsCategory] = []
        if Self.hasText(raw["hostname"]), Self.integer(raw["statsFrequency"], in: 0...65_535) {
            categories.append(.general)
        }
        let reportsPool = usesEssentialsPools
            ? MinerPoolRole.allCases.contains { MinerEssentialsPoolBaseline.reportedConnection($0, raw: raw) != nil }
            : Self.hasText(raw["stratumURL"]) && Self.hasText(raw["fallbackStratumURL"])
                && Self.integer(raw["primaryPoolIndex"], in: 0...7) && Self.integer(raw["secondaryPoolIndex"], in: 0...7)
                && raw["pools"]?.arrayValue?.contains(where: { Self.hasText($0["stratumURL"]) }) == true
        if driverCapabilities.canSetPool, reportsPool {
            categories.append(.pools)
        }
        if let rotation = raw["rotation"]?.doubleValue, [0, 90, 180, 270].contains(rotation),
           raw["invertscreen"]?.boolValue != nil, Self.integer(raw["displayTimeout"], in: -1...65_535) {
            categories.append(.display)
        }
        if cooling { categories.append(.cooling) }
        if tuning { categories.append(.tuning) }
        return categories
    }

    func showsSettingsHub(in mode: FleetPreferences.DashboardMode, usesEssentialsPools: Bool = false) -> Bool {
        !settingsCategories(usesEssentialsPools: usesEssentialsPools).isEmpty
            || quickActions.contains(.restart) || (mode == .full && rawAPI)
            || (rawAPI && hasFreshLiveFields && ["canaan", "canaannano3"].contains(driverCapabilities.family))
            || (rawAPI && !driverCapabilities.isReadOnly
                && !MinerFirmwareExtras.controls(for: driverCapabilities.family).isEmpty)
    }

    private static func hasText(_ value: JSONValue?) -> Bool {
        guard case let .string(text)? = value else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func integer(_ value: JSONValue?, in range: ClosedRange<Int>) -> Bool {
        guard let number = value?.doubleValue, let integer = Int(exactly: number) else { return false }
        return range.contains(integer)
    }

    @MainActor func firmwareUpdate(_ notice: FirmwareUpdateNotice?) -> FirmwareUpdateNotice? {
        guard rawAPI, firmwareStatus == .supported, let notice, !notice.checkFailed,
              notice.isUpdateAvailable, notice.currentVersion == FirmwareUpdateStore.currentVersion(from: info)
        else { return nil }
        return notice
    }
}

extension NumberFirstPreview {
    static let sampleFirmwareVersion = "v0.0.1"

    static var minerFirmwareNotice: FirmwareUpdateNotice {
        FirmwareUpdateNotice(
            currentVersion: sampleFirmwareVersion,
            releases: [FirmwareRelease(version: "v0.0.2", url: nil)],
            checkedAt: .now,
            checkFailed: false
        )
    }

    static func minerAvailability(_ info: MinerInfo) -> MinerNumberFirstAvailability {
        guard minerDetail else {
            return .init(info: info, infoStatus: .notChecked, settingsStatus: .notChecked, firmwareStatus: .notChecked)
        }
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-test-preview-detail-read-only") {
            let denied = MinerProbeStatus.failed(message: "HTTP 403")
            return .init(info: info, infoStatus: .supported, settingsStatus: denied, firmwareStatus: denied)
        }
        if arguments.contains("--ui-test-preview-detail-limited") {
            return .init(info: info, infoStatus: .supported, settingsStatus: .notChecked, firmwareStatus: .notChecked)
        }
        return .init(info: info, infoStatus: .supported, settingsStatus: .supported, firmwareStatus: .supported,
                     actionStatuses: Dictionary(uniqueKeysWithValues: MinerDetailQuickAction.allCases.map { ($0, .supported) }))
    }

    /// Info and reported fields permit opening the existing validated editors. They do not
    /// prove a write endpoint. Commands are tried only with a fresh read and an explicit tap.
    @MainActor static func minerAvailability(
        _ info: MinerInfo, device: MinerDevice, store: FleetStore
    ) -> MinerNumberFirstAvailability {
        if store.isDemo { return minerAvailability(info) }
        let validInfo = device.kind != .xmrig && MinerShapeValidator.isValidInfoShape(.object(info.raw))
        let canRequest = usesLivePhoneLayouts && validInfo && MinerWriteAvailability.allows(
            store.snapshot(for: device.id), device: device, currentDevices: store.devices, isDemo: store.isDemo
        )
        let hasDeviceIdentity = MinerInlineActionState.identity(from: info) != nil
        let asic = store.capabilities.reports[device.id]?.asic
        let family = device.firmwareFamily
            ?? MinerFirmwareAdapter.detectedFamily(from: info, asic: asic)
            ?? info.raw["firmwareFamily"]?.stringValue
        let driverCaps = MinerDriverCapabilities.forFamily(family, info: info)
        let supportedActions = Set(MinerDetailQuickAction.allCases.filter { action in
            switch action {
            case .identify: driverCaps.canIdentify
            case .pause, .resume: driverCaps.canPause || driverCaps.canShutdown
            case .restart: driverCaps.canRestart
            }
        })
        return .init(
            info: info,
            infoStatus: validInfo ? .supported : .notChecked,
            settingsStatus: .notChecked,
            firmwareStatus: .notChecked,
            hasFreshLiveFields: canRequest && !driverCaps.isReadOnly,
            liveActionCandidates: canRequest && hasDeviceIdentity ? supportedActions : [],
            driverCapabilities: driverCaps
        )
    }
}

extension MinerDetailView {
    func numberFirstTelemetry(_ info: MinerInfo) -> some View {
        let availability = NumberFirstPreview.minerAvailability(info, device: device, store: store)
        let usesEssentialsPools = !store.isDemo && dashboardMode == .essentials
        let showsSettings = guidedEssentials || (store.isDemo ? NumberFirstPreview.settingsHub : NumberFirstPreview.usesLivePhoneLayouts)
            && availability.showsSettingsHub(in: dashboardMode, usesEssentialsPools: usesEssentialsPools)
        return VStack(alignment: .leading, spacing: 10) {
            hashrateHero(info, compact: true)
            heroConditions(info, compact: true)
            minerHistoryCard
            if dashboardMode == .full,
               snapshot?.history.contains(where: { $0.value.isFinite && $0.value >= 0 }) == true {
                uptimeHeatmap.fleetCard(padding: FleetSurfaceSpacing.cardInset)
            }
            if availability.cooling || availability.tuning || !availability.quickActions.isEmpty || showsSettings {
                numberFirstControls(availability, showsSettings: showsSettings)
            }
            if MiningDifficultyFormat.parse(info.raw["bestDiff"]) != nil
                || MiningDifficultyFormat.parse(info.raw["bestSessionDiff"]) != nil {
                bestShares(info, compact: true)
            }
            if dashboardMode == .full {
                numberFirstFullDetails(availability)
            }
        }
    }

    func numberFirstControls(_ availability: MinerNumberFirstAvailability, showsSettings: Bool) -> some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let actions = availability.quickActions
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 1))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
        return VStack(alignment: .leading, spacing: 6) {
            Label("Control miner", systemImage: "slider.horizontal.3")
                .fleetFont(.subheadline, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 1)
            if availability.cooling || availability.tuning {
                layout {
                    if availability.cooling {
                        numberFirstControl("Cooling", symbol: "fan", category: .cooling)
                    }
                    if availability.tuning {
                        numberFirstControl("Tuning", symbol: "gauge.with.dots.needle.67percent", category: .tuning)
                    }
                }
            }
            if !actions.isEmpty {
                if !store.isDemo && dashboardMode == .essentials && actions.contains(.restart) {
                    Text("Actions send immediately. Restart briefly stops mining.")
                        .fleetFont(.caption).foregroundStyle(FleetTheme.warning)
                }
                FleetMinerDetailGrid(maximumColumns: stacked ? 1 : 2,
                                     minimumColumnWidth: 140, spacing: 6) {
                    ForEach(actions, id: \.self) { action in
                        if dashboardMode == .essentials {
                            VStack(alignment: .leading, spacing: 6) {
                                previewQuickAction(action)
                                if stacked, previewQuickActionResult == action {
                                    numberFirstQuickActionResult(action)
                                }
                            }
                        } else {
                            quickAction(action, compact: true)
                        }
                    }
                }
                if store.isDemo && !stacked, dashboardMode == .essentials, let result = previewQuickActionResult,
                   availability.quickActions.contains(result) {
                    numberFirstQuickActionResult(result)
                }
            }
            if showsSettings {
                numberFirstControl("Miner settings", symbol: "gearshape", category: nil)
                    .fleetTourTarget("guide.minerSettings")
            }
        }
        .foregroundStyle(FleetTheme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fleetCard(padding: 10, border: .clear, cornerRadius: 16)
    }

    func numberFirstQuickActionResult(_ action: MinerDetailQuickAction) -> some View {
        MinerQuickActionPreviewResult(action: action)
            .padding(.horizontal, 4)
            .accessibilityIdentifier("detail.previewControls.result")
    }

    func numberFirstControl(_ title: String, symbol: String, category: MinerSettingsCategory?) -> some View {
        NavigationLink {
            settingsDestination(category)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(FleetTheme.accent).accessibilityHidden(true)
                Text(title).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 2)
                Image(systemName: "chevron.right")
                    .fleetFont(.caption2, weight: .semibold)
                    .foregroundStyle(FleetTheme.secondary)
                    .accessibilityHidden(true)
            }
            .fleetFont(.subheadline, weight: .semibold)
            .foregroundStyle(FleetTheme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(FleetTheme.raised, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("detail.previewControls.\(category?.rawValue ?? "settings")")
        .accessibilityHint("Opens settings for review. No change is sent.")
    }

    @ViewBuilder private func numberFirstFullDetails(_ availability: MinerNumberFirstAvailability) -> some View {
        let info = availability.info
        numberFirstDeviceReadings(info)
        if availability.rawAPI {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tools")
                    .fleetFont(.subheadline, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                NavigationLink {
                    MinerPreviewInfoResponse(info: info, isDemo: store.isDemo)
                } label: {
                    toolRow("Raw API", subtitle: store.isDemo ? "Inspect the stored sample" : "Inspect the last readings", symbol: "curlybraces")
                }
                .accessibilityIdentifier("detail.rawAPI")
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func numberFirstDeviceReadings(_ info: MinerInfo) -> some View {
        let diagnostics = MinerDiagnosticsModel(info: info)
        let thermal = diagnostics.thermal
        let electrical = diagnostics.electrical
        let readings = [
            MinerPreviewReading("Fan speed", thermal.fan1RPM, "RPM"),
            MinerPreviewReading("Fan 2 speed", thermal.fan2RPM, "RPM"),
            MinerPreviewReading("Fan duty", thermal.fanSpeedPercent, "%"),
            MinerPreviewReading("Voltage regulator", thermal.vrTempCelsius, "°C"),
            MinerPreviewReading("Temperature 2", thermal.secondaryChipTempCelsius, "°C"),
            MinerPreviewReading("Target temperature", thermal.targetTempCelsius, "°C"),
            MinerPreviewReading("Input voltage", electrical.inputVoltageMV.map { $0 / 1_000 }, "V", decimals: 2),
            MinerPreviewReading("Configured frequency", electrical.configuredFrequencyMHz, "MHz"),
            MinerPreviewReading("Actual frequency", electrical.actualFrequencyMHz, "MHz"),
            MinerPreviewReading("Configured core voltage", electrical.configuredCoreVoltageMV, "mV"),
            MinerPreviewReading("Actual core voltage", electrical.actualCoreVoltageMV, "mV"),
            MinerPreviewReading("Efficiency", electrical.efficiencyJoulesPerTerahash, "J/TH", decimals: 1),
            MinerPreviewReading("Wi-Fi signal", diagnostics.system.wifiRSSI, "dBm"),
            MinerPreviewReading(title: "Firmware version", value: diagnostics.system.firmwareVersion)
        ].filter { $0.value != nil }
        if !readings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Device readings")
                    .fleetFont(.subheadline, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                ForEach(readings, id: \.title) { reading in
                    if let value = reading.value {
                        LabeledContent(reading.title, value: value)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(reading.title)
                            .accessibilityValue(value)
                            .accessibilityIdentifier("detail.previewReading.\(reading.title)")
                    }
                }
            }
            .fleetFont(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fleetCard(padding: 10, border: .clear, cornerRadius: 16)
        }
    }
}

private struct MinerPreviewReading {
    let title: String
    let value: String?

    init(title: String, value: String?) {
        self.title = title
        self.value = value
    }

    init(_ title: String, _ value: Double?, _ unit: String, decimals: Int = 0) {
        self.init(title: title, value: value.map { FleetFormat.measurement($0, unit: unit, decimals: decimals) })
    }
}

/// Shows the same sanitized Info response as the cards without making a request.
struct MinerPreviewInfoResponse: View {
    let info: MinerInfo
    let isDemo: Bool

    var body: some View {
        FleetSettingsForm {
            FleetSettingsSection(isDemo ? "Stored sample · no request sent" : "Last readings · no request sent") {
                Text((try? Self.sanitized(.object(info.raw)).prettyPrinted()) ?? "Readings could not be displayed.")
                    .fleetFont(.caption, design: .monospaced)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("detail.previewRawInfo")
            }
            .listRowBackground(FleetTheme.surface)
        }
        .navigationTitle("System info")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(FleetTheme.canvas)
    }

    private static func sanitized(_ value: JSONValue) -> JSONValue {
        switch value {
        case .object(let object):
            let privateFields = ["stratumuser", "fallbackstratumuser", "ssid", "wifissid", "mac", "macaddr"]
            return .object(Dictionary(uniqueKeysWithValues: object.map { key, child in
                let lower = key.lowercased()
                let privateValue = privateFields.contains(lower)
                    || JSONRedactor.sensitiveKeyFragments.contains { lower.contains($0) }
                return (key, privateValue ? .string("[redacted]") : sanitized(child))
            }))
        case .array(let values): return .array(values.map(sanitized))
        default: return value
        }
    }
}
