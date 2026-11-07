import SwiftUI
import HashFleetCore

/// Supporting view components and models used by MinerDetailView and its extensions.
/// Moved out of MinerDetailView.swift for file-length hygiene; behavior unchanged.
/// A real SwiftUI body boundary, not a computed `some View` helper. Keeping the
/// builder deferred prevents the full telemetry tuple being built on its parent's
/// stack, which overflowed the physical iPhone main-thread stack in Debug builds.
struct MinerDetailSection<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View { content() }
}

/// Store only metric data, rather than embedding the entire styled tile value into
/// every grid and its ancestors before SwiftUI has a chance to evaluate the tile.
struct MinerDetailMetric: View {
    let title: String
    let value: Double?
    let unit: String
    let symbol: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let displayValue = value.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "N/A"
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).fleetFont(.caption2).foregroundStyle(FleetTheme.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(displayValue)
                    .fleetFont(.title3, weight: .semibold, design: .rounded).minimumScaleFactor(0.5)
                    .monospacedDigit()
                    .fleetNumericUpdate(displayValue, reduceMotion: reduceMotion)
                Text(unit).fleetFont(.caption2).foregroundStyle(FleetTheme.secondary)
            }.lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .fleetCard(padding: FleetSurfaceSpacing.cardInset)
        // The compact "N/A" needs the same unambiguous meaning the rest of the app uses: the value
        // was not reported, which says nothing about whether the hardware has that sensor.
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("detail.metric.\(title)")
        .accessibilityLabel(
            value.map { "\(title), \($0.formatted(.number.precision(.fractionLength(0...1)))) \(unit)" }
                ?? "\(title), not reported"
        )
    }
}

/// The content closure is evaluated by SwiftUI only inside this card's own body.
/// A folded card does not eagerly construct its telemetry subtree.
struct MinerDetailCollapsibleCard<Content: View>: View {
    let spec: MinerDetailCardSpec
    let expanded: Binding<Bool>
    let device: MinerDevice
    let store: FleetStore
    let insights: MiningInsightsStore?
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MinerDetailCardHeader(
                spec: spec,
                expanded: expanded,
                device: device,
                store: store,
                insights: insights
            )
            if expanded.wrappedValue {
                MinerDetailSection(content: content)
                    .padding([.horizontal, .bottom], 16)
                    .padding(.top, 12)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: expanded.wrappedValue ? .topLeading : .leading)
        .fleetCard(padding: 0)
    }
}

/// Independent small header body keeps disclosure and settings sibling controls,
/// with the same identifiers, touch targets, navigation and Reduce Motion behavior.
struct MinerDetailCardHeader: View {
    let spec: MinerDetailCardSpec
    let expanded: Binding<Bool>
    let device: MinerDevice
    let store: FleetStore
    let insights: MiningInsightsStore?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title3) private var detailIconColumnWidth: CGFloat = 28

    var body: some View {
            HStack(alignment: .center, spacing: 0) {
                Button {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.18)) {
                        expanded.wrappedValue.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        sectionLabel
                        Image(systemName: "chevron.right")
                            .fleetFont(.caption, weight: .semibold)
                            .rotationEffect(.degrees(expanded.wrappedValue ? 90 : 0))
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44,
                           maxHeight: expanded.wrappedValue ? nil : .infinity, alignment: .leading)
                    .padding(16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(spec.id)
                .accessibilityValue(expanded.wrappedValue ? "Expanded" : "Collapsed")
                .accessibilityHint(
                    expanded.wrappedValue
                        ? "Hides these readings. Does not change miner settings."
                        : "Shows these readings. Does not change miner settings."
                )
                NavigationLink {
                    if spec.settings == .tuning {
                        // Same direct route as the quick link: avoids nesting the unified
                        // tuning workspace inside the miner settings hub.
                        MinerTuningSessionView(device: device, store: store, insights: insights)
                    } else {
                        MinerSettingsView(device: device, store: store, insights: insights, initialCategory: spec.settings)
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .fleetFont(.body, weight: .medium)
                        .foregroundStyle(FleetTheme.accent)
                        .frame(width: 44, height: 44)
                        .padding(.trailing, 16)
                        .frame(minHeight: 44, maxHeight: expanded.wrappedValue ? nil : .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(spec.title) settings")
                .accessibilityIdentifier(spec.settingsID)
                .accessibilityHint("Opens the form. Changes still require review and confirmation.")
            }
    }

    private var sectionLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: spec.symbol)
                .fleetFont(.title3).foregroundStyle(FleetTheme.accent)
                .frame(width: detailIconColumnWidth)
            VStack(alignment: .leading, spacing: 3) {
                Text(spec.title).fleetFont(.headline).foregroundStyle(FleetTheme.ink)
                Text(spec.subtitle).fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

}

struct FirmwareCheckIdentity: Equatable {
    let deviceID: UUID
    let updatedAt: Date?
}

struct MinerNavigationIdentity: Equatable {
    let deviceName: String
    let poolName: String?
    let coin: MiningPoolCoin?
    let market: CoinGeckoMarket?
}

private struct MinerNavigationIdentityKey: EnvironmentKey {
    static let defaultValue: MinerNavigationIdentity? = nil
}

extension EnvironmentValues {
    var minerNavigationIdentity: MinerNavigationIdentity? {
        get { self[MinerNavigationIdentityKey.self] }
        set { self[MinerNavigationIdentityKey.self] = newValue }
    }
}

struct MinerNavigationTitle: View {
    let pageTitle: String?
    let identifier: String?
    @Environment(\.minerNavigationIdentity) private var identity

    init(pageTitle: String?, identifier: String? = nil) {
        self.pageTitle = pageTitle
        self.identifier = identifier
    }

    var body: some View {
        VStack(spacing: pageTitle == nil ? 0 : 1) {
            #if !os(macOS)
            if let pageTitle {
                Text(pageTitle)
                    .fleetFont(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            #endif
            if let identity {
                HStack(spacing: 6) {
                    Text(identity.deviceName)
                        .fleetFont(pageTitle == nil ? .headline : .caption2, weight: .semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    if let coin = identity.coin {
                        CoinGeckoIcon(
                            coin: coin,
                            fallbackTicker: identity.market?.ticker ?? coin.ticker,
                            size: pageTitle == nil ? 22 : 18
                        )
                    }
                }
            }
        }
        .foregroundStyle(FleetTheme.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(identifier ?? "miner.navigationTitle")
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if let pageTitle { parts.append(pageTitle) }
        if let identity {
            parts.append(identity.deviceName)
            if let coin = identity.coin { parts.append(identity.market?.ticker ?? coin.ticker) }
        }
        return parts.joined(separator: ", ")
    }
}

/// The pool actually in use, rather than the legacy `stratumURL` field.
///
/// Audited ESP-Miner master system_api_json.c, 2026-09-06: `stratumURL` is emitted for backwards
/// compatibility from the *primary* pool slot even while `isUsingFallbackStratum` is 1, so showing
/// it unconditionally can name a pool the miner is not connected to. When the fallback flag is set
/// this reads the fallback fields instead and labels the row accordingly. If the fallback flag is set
/// but fallbackStratumURL is absent, it never falls back to stratumURL (which is primary). Firmware that
/// reports neither flag nor URL simply shows "Not reported"; nothing is guessed.
struct MinerActivePool: Equatable, Sendable {
    let title: String
    let value: String
    let isUsingFallback: Bool

    init(info: MinerInfo) {
        let fallbackFlag = info.raw["isUsingFallbackStratum"]?.boolValue
        let usingFallback = fallbackFlag == true
        let reportsFlag = fallbackFlag != nil
        isUsingFallback = usingFallback

        // Rotation firmware reports the actual connection separately from configured primary/fallback.
        // Do not use legacy URLs when the explicit active slot is invalid or missing from the table.
        if info.raw["activePoolIndex"] != nil {
            let selected = ConfiguredMiningPool.resolve(info: info).first(where: { $0.isActive == true })
            if let selected, let slot = ConfiguredMiningPool.reportedActiveSlotID(info: info) {
                title = "Pool · active slot \(slot)"
                value = selected.host
            } else {
                title = "Pool · active not reported"
                value = MinerCapabilityPresentation.notReported
            }
            return
        }

        let poolsArray = info.raw["pools"]?.arrayValue?.compactMap(\.objectValue)
        let primarySlotId = info.raw["primaryPoolIndex"]?.intValue
        let secondarySlotId = info.raw["secondaryPoolIndex"]?.intValue

        func slotUrl(for slotId: Int?) -> String? {
            guard let slotId, let pools = poolsArray else { return nil }
            guard let match = pools.first(where: { $0["id"]?.intValue == slotId }) else { return nil }
            return MinerCapabilityPresentation.text(match["url"])
                ?? MinerCapabilityPresentation.text(match["stratumURL"])
        }

        if usingFallback {
            title = "Pool · fallback in use"
            // Missing fallback URL must never fall back to primary stratumURL.
            let fallbackUrl = slotUrl(for: secondarySlotId)
                ?? MinerCapabilityPresentation.text(info.raw["fallbackStratumURL"])
            value = fallbackUrl ?? MinerCapabilityPresentation.notReported
        } else if reportsFlag {
            // Fallback flag is explicitly false: primary pool is in use.
            title = "Pool · primary"
            let primaryUrl = slotUrl(for: primarySlotId)
                ?? MinerCapabilityPresentation.text(info.raw["stratumURL"])
                ?? MinerCapabilityPresentation.text(info.raw["poolURL"])
            value = primaryUrl ?? MinerCapabilityPresentation.notReported
        } else {
            // Flag is absent: we cannot claim primary is connected.
            title = "Pool · configured primary"
            let primaryUrl = slotUrl(for: primarySlotId)
                ?? MinerCapabilityPresentation.text(info.raw["stratumURL"])
                ?? MinerCapabilityPresentation.text(info.raw["poolURL"])
            value = primaryUrl ?? MinerCapabilityPresentation.notReported
        }
    }
}

/// Fault, operational, and connection states the miner explicitly reports about itself.
///
/// Audited ESP-Miner master system_api_json.c, 2026-09-06:
/// - `miningPaused` is explicitly reported as a boolean or 0/1; never inferred from temperature or model.
/// - `power_fault` and `hardware_fault` are added only while a fault is active and carry a human-readable message.
/// - `overheat_mode` is always present as 0/1.
/// - `isUsingFallbackStratum` is 0/1.
/// Share statistics note: uses "may reset" rather than a categorical reset claim unless proven by current observation.
struct MinerReportedAlerts: Equatable, Sendable {
    let messages: [String]
    var isEmpty: Bool { messages.isEmpty }

    init?(info: MinerInfo) {
        var found: [String] = []

        if info.raw["miningPaused"]?.boolValue == true {
            found.append("Mining is paused by the miner. Hashes and shares are currently suspended.")
        }
        if info.raw["overheat_mode"]?.boolValue == true {
            found.append("Overheat protection is active. The miner reports it throttled or stopped itself. "
            + "Check cooling before changing settings.")
        }
        if let fault = MinerCapabilityPresentation.text(info.raw["power_fault"]) {
            found.append("Power fault reported: \(fault)")
        }
        if let fault = MinerCapabilityPresentation.text(info.raw["hardware_fault"]) {
            found.append("Hardware fault reported: \(fault)")
        }
        if info.raw["isUsingFallbackStratum"]?.boolValue == true {
            let pool = MinerCapabilityPresentation.text(info.raw["fallbackStratumURL"])
            found.append(
                "Mining on the fallback pool\(pool.map { " (\($0))" } ?? ""). "
                    + "Share statistics may reset when switching pools."
            )
        }
        guard !found.isEmpty else { return nil }
        messages = found
    }
}

/// Grouped parameters for the collapsible detail cards. Keeps helpers under the parameter limit.
struct MinerDetailCardSpec {
    let title: String
    let subtitle: String
    let symbol: String
    let id: String
    let settings: MinerSettingsCategory
    let settingsID: String
}

/// One promoted hero reading (temperature or power) on the miner detail screen.
struct MinerHeroReading {
    let title: String
    let symbol: String
    let value: Double?
    let unit: String
    let caption: String
    let id: String

    func accessibilityLabel(display: String) -> String {
        "\(title), \(display) \(value == nil ? "" : unit), \(caption)"
    }
}

/// Owns the only dismiss dependency for the miner page. Keeping `\.dismiss` in this leaf view means
/// navigation changes re-render one button, not the entire MinerDetailView body.
struct MinerRemoveFromFleetButton: View {
    let store: FleetStore
    let device: MinerDevice
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Remove from fleet", role: .destructive) {
            store.remove(device)
            dismiss()
        }
    }
}
