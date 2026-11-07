import SwiftUI
import HashFleetCore

/// A friendly, manual compatibility check.
///
/// Opening this screen contacts nothing. A check runs only when the person taps the button, and it
/// performs exactly two read operations: `GET /api/system/info` and `GET /api/system/asic`. No
/// settings are written, no presets are applied and no other endpoint is probed. In demo mode the
/// button is disabled and this screen only describes the built-in sample, so no request is possible
/// and no probe result is invented.
///
/// Wording rules enforced here:
/// - A field the device did not send is reported as "Not reported", never as unsupported hardware.
/// - A transport, authentication or server error is "Could not check", never "Unsupported".
/// - Nothing is inferred from the ASIC or board name. Unknown models stay fully usable, because
///   support is read from what the device actually reports rather than from any built-in list.
struct MinerCompatibilityView: View {
    let device: MinerDevice
    @Bindable var store: FleetStore
    var insights: MiningInsightsStore?

    /// Checks are user-driven. `.task(id:)` only acts once a tap has advanced the request counter,
    /// so appearing, returning from a child screen or a state change never triggers a request.
    @State private var checkRequest = 0
    @State private var handledRequest = 0

    private var report: MinerCapabilityReport? { store.capabilities.reports[device.id] }
    private var isChecking: Bool { store.capabilities.checking.contains(device.id) }
    /// Demo mode never probes, so the sample telemetry is shown as a preview of the layout only.
    private var demoInfo: MinerInfo? { store.isDemo ? store.snapshot(for: device.id)?.info : nil }

    private var navigationIdentity: MinerNavigationIdentity {
        let context = MinerMiningContext.resolve(info: store.snapshot(for: device.id)?.info)
        let coin = context.pool?.coin
        return MinerNavigationIdentity(
            deviceName: device.name,
            poolName: context.pool == nil ? nil : context.providerLabel,
            coin: coin,
            market: coin.flatMap { insights?.coinMarkets[$0] }
        )
    }

    var body: some View {
        FleetSettingsForm {
            summarySection
            actionSection
            if let report, !store.isDemo {
                resultSection(report)
                identitySection(info: report.info, asic: report.asic)
                rawSection(info: report.info, asic: report.asic)
            } else if let demoInfo {
                identitySection(info: demoInfo, asic: nil)
                rawSection(info: demoInfo, asic: nil)
            }
            footerSection
        }
        .navigationTitle("Check compatibility")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(FleetTheme.canvas)
        .tint(FleetTheme.accent)
        .toolbar {
            ToolbarItem(placement: .principal) {
                MinerNavigationTitle(pageTitle: "Check compatibility")
            }
        }
        .environment(\.minerNavigationIdentity, navigationIdentity)
        .task(id: checkRequest) {
            guard checkRequest > handledRequest, !store.isDemo else { return }
            handledRequest = checkRequest
            await store.capabilities.check(device: device, isDemo: store.isDemo)
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        FleetSettingsSection(header: AnyView(Text(device.name))) {
            FleetSettingsRow(showsSeparator: false) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(summary.title, systemImage: summary.symbol)
                            .fleetFont(.headline)
                            .foregroundStyle(summary.tint)
                        Spacer(minLength: 12)
                        if isChecking { ProgressView() }
                    }
                    Text(summary.detail)
                        .fleetFont(.footnote)
                        .foregroundStyle(FleetTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("compatibility.status")
            }
        }
    }

    private struct Summary {
        let title: String
        let detail: String
        let symbol: String
        let tint: Color
    }

    private var summary: Summary {
        if store.isDemo {
            return Summary(
                title: "Demo preview",
                detail:
                    "Demo mode contacts no miner, so compatibility is never checked here. The fields below "
                        + "come from the built-in sample and show what a real check would report.",
                symbol: "lock.fill",
                tint: FleetTheme.secondary
            )
        }
        if isChecking {
            return Summary(
                title: "Checking…",
                detail: "Reading system info and the ASIC configuration once. Nothing is being written.",
                symbol: "arrow.triangle.2.circlepath",
                tint: FleetTheme.accent
            )
        }
        guard let report else {
            return Summary(
                title: "Not checked yet",
                detail: "Check system info and ASIC references. Ordinary monitoring may already refresh Info.",
                symbol: "questionmark.circle",
                tint: FleetTheme.secondary
            )
        }
        let info = report.infoStatus
        let asic = report.asicStatus
        if info.isFailed || asic.isFailed {
            return Summary(
                title: "Check incomplete",
                detail:
                    "A read failed, so support is still unknown. This does not mean your hardware is unsupported. " +
                        "Try again below.",
                symbol: "exclamationmark.triangle",
                tint: FleetTheme.warning
            )
        }
        switch (info.isSupported, asic.isSupported) {
        case (true, true):
            return Summary(
                title: "Detected ESP-Miner-compatible API",
                detail:
                    "This miner answered both the system info and ASIC configuration reads. "
                        + "The app adapts its forms to the fields it actually reported.",
                symbol: "checkmark.seal",
                tint: FleetTheme.positive
            )
        case (true, false):
            return Summary(
                title: "Partly supported",
                detail:
                    "Detected ESP-Miner-compatible API for system info. The ASIC read is unavailable on this firmware, "
                        + "but monitoring and manual settings remain usable.",
                symbol: "checkmark.circle",
                tint: FleetTheme.accent
            )
        case (false, true):
            return Summary(
                title: "Partly supported",
                detail:
                    "The ASIC configuration read works, but this firmware does not serve system info. "
                        + "Telemetry and adaptive forms will stay limited.",
                symbol: "checkmark.circle",
                tint: FleetTheme.accent
            )
        case (false, false):
            return Summary(
                title: "Not served by this firmware",
                detail:
                    "The miner replied, but neither read is implemented by its firmware. Tools & firmware and the JSON "
                        + "editors remain available if you know what this device expects.",
                symbol: "slash.circle",
                tint: FleetTheme.warning
            )
        }
    }

    // MARK: - Actions

    private var actionSection: some View {
        FleetSettingsSection("Manual check") {
            FleetSettingsRow {
            // One button covers first check and retry so the page never shows two competing actions.
            Button(buttonTitle) { checkRequest += 1 }
                .disabled(isChecking || store.isDemo)
                .accessibilityIdentifier(lastCheckFailed ? "compatibility.retry" : "compatibility.check")
            }
            if lastCheckFailed {
                FleetSettingsRow {
                    Text("The previous attempt did not finish. Retrying performs the same two reads again.")
                        .fleetFont(.footnote)
                        .foregroundStyle(FleetTheme.warning)
                }
            }
            if store.isDemo {
                FleetSettingsRow {
                    Label(
                        "Checking is disabled in demo mode. No miner is contacted and no result is invented.",
                        systemImage: "lock.fill"
                    )
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.secondary)
                }
            }
            FleetSettingsRow(showsSeparator: false) {
                Text("Reads Info and ASIC once. Never changes settings.")
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.secondary)
            }
        }
    }

    private var lastCheckFailed: Bool {
        guard !store.isDemo, let report else { return false }
        return report.infoStatus.isFailed || report.asicStatus.isFailed
    }

    private var buttonTitle: String {
        if isChecking { return "Checking…" }
        if lastCheckFailed { return "Try again" }
        return report == nil ? "Check compatibility" : "Check again"
    }

    private func rawSection(info: MinerInfo?, asic: JSONValue?) -> some View {
        FleetSettingsSection(header: AnyView(Text("Details")), footer: AnyView(
            Text("Raw responses may contain private network information or credentials. Keep them private.")
        )) {
            FleetSettingsRow {
                DisclosureGroup("Raw system info response") {
                    rawText(info.map { JSONValue.object($0.raw) })
                }
                .accessibilityIdentifier("compatibility.rawInfo")
            }
            FleetSettingsRow(showsSeparator: false) {
                DisclosureGroup("Raw ASIC response") {
                    rawText(asic)
                }
                .accessibilityIdentifier("compatibility.rawAsic")
            }
        }
    }

    @ViewBuilder
    private func rawText(_ value: JSONValue?) -> some View {
        if let value, let text = try? value.prettyPrinted() {
            Text(text)
                .font(FleetTheme.mono(11))
                .textSelection(.enabled)
        } else {
            Text(
                store.isDemo
                    ? "The demo sample does not include this response." : "Nothing was returned for this read."
            )
            .fleetFont(.caption)
            .foregroundStyle(FleetTheme.secondary)
        }
    }

    private var footerSection: some View {
        FleetSettingsSection {
            FleetSettingsRow(showsSeparator: false) {
                DisclosureGroup("How compatibility works") {
                    Text(
                        "One check reads GET /api/system/info and GET /api/system/asic. " +
                            "It does not test other endpoints or change settings. Reported fields are not proof " +
                            "that firmware accepts writes or that tuning is safe. Every change still requires review " +
                            "and APPLY confirmation. Unknown models remain usable, and Tools & firmware stays available."
                    )
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.secondary)
                }
            }
        }
    }
}

#Preview("Compatibility · demo") {
    let store = FleetStore(defaults: UserDefaults(suiteName: "app.hashfleet.compatibility-preview")!)
    store.loadDemo()
    return NavigationStack {
        MinerCompatibilityView(device: store.devices[0], store: store)
    }
}

/// Shared, presentation-only helpers so the settings screens describe capabilities with the same
/// vocabulary as this page. Nothing here infers support from a model name.
enum MinerCapabilityPresentation {
    static let notReported = "Not reported"

    /// Returns a count only when firmware reports it or its built-in board version
    /// is in the audited device matrix. Temperature keys and ASIC model strings are
    /// not evidence of chip count: `temp2` is emitted even without a second reading,
    /// and BM1370 boards can have one, two, or six ASICs.
    static func asicCount(info: MinerInfo?) -> Int? {
        if let count = info?.raw["asicCount"]?.intValue, count > 0 {
            return count
        }
        if let reported = text(info?.raw["asicCount"]).flatMap(Int.init), reported > 0 {
            return reported
        }
        guard let board = boardVersion(info: info, asic: nil)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !board.isEmpty else {
            return nil
        }
        return boardASICCounts[board]
    }

    static func asicDescriptor(info: MinerInfo?) -> String? {
        let model = asicModel(info: info, asic: nil)
        return asicCount(info: info).map { "\($0)× \(model ?? "ASIC")" } ?? model
    }

    private static let boardASICCounts: [String: Int] = [
        "2.2": 1, "102": 1,
        "0.11": 1, "201": 1, "202": 1, "203": 1, "204": 1, "205": 1, "207": 1,
        "302": 6, "303": 6,
        "400": 1, "401": 1, "402": 1, "403": 1,
        "600": 1, "601": 1, "602": 1, "603": 1,
        "650": 2, "801": 2, "1300": 6, "1201": 2,
        "701": 6, "702": 6
    ]

    static func asicModel(info: MinerInfo?, asic: JSONValue?) -> String? {
        text(info?.raw["ASICModel"]) ?? text(info?.raw["asicModel"])
            ?? text(asic?["ASICModel"]) ?? text(asic?["asicModel"])
    }

    static func boardVersion(info: MinerInfo?, asic: JSONValue?) -> String? {
        text(info?.raw["boardVersion"]) ?? text(asic?["boardVersion"])
    }

    static func firmwareVersion(info: MinerInfo?) -> String? {
        text(info?.raw["version"]) ?? text(info?.raw["firmwareVersion"])
    }

    static func axeOSVersion(info: MinerInfo?) -> String? {
        text(info?.raw["axeOSVersion"])
    }

    static func hostname(info: MinerInfo?) -> String? {
        text(info?.raw["hostname"]) ?? text(info?.raw["fullHostname"])
    }

    /// A trimmed, non-empty reported string, or `nil` when the device did not report one.
    /// Numbers are accepted because some firmware sends versions and identifiers unquoted.
    static func text(_ value: JSONValue?) -> String? {
        guard let value else { return nil }
        switch value {
        case .string(let raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .number, .integer, .unsignedInteger:
            return value.stringValue
        default:
            return nil
        }
    }

    /// Wording for a form field the current telemetry does not include. Never says "unsupported":
    /// a missing field can mean older firmware, a partial payload or simply no recent read.
    static func missingFieldNote(_ label: String, key: String) -> String {
        "This miner did not report \(label) (\(key)), so there is no current value to start from. " +
            "That is not proof the firmware rejects it. Enter a value if you know this device accepts it, " +
            "and review the exact change before sending."
    }
}
