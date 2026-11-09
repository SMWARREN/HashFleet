import SwiftUI
import HashFleetCore

struct FleetBestShareCelebrationBanner: View {
    let event: MinerBestShareEvent
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .fleetFont(.title3)
                .foregroundStyle(FleetTheme.accent)
                .frame(width: 40, height: 40)
                .background(FleetTheme.accent.opacity(0.14), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("NEW PERSONAL BEST")
                    .font(FleetTheme.mono(10))
                    .foregroundStyle(FleetTheme.accent)
                Text("\(event.minerName) · \(event.kind.title) share")
                    .fleetFont(.subheadline, weight: .semibold)
                    .foregroundStyle(FleetTheme.ink)
                Text(event.displayValue + " difficulty")
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Dismiss", systemImage: "xmark") {
                dismiss()
            }
            .labelStyle(.iconOnly)
            .fleetFont(.caption, weight: .bold)
            .foregroundStyle(FleetTheme.secondary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("Dismiss best share celebration")
        }
        .padding(FleetSurfaceSpacing.cardInset)
        .background(FleetTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(FleetTheme.accent.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dashboard.bestShareCelebration")
        .accessibilityLabel(
            "New personal best from \(event.minerName), \(event.kind.title) share, \(event.displayValue) difficulty"
        )
        .accessibilityAction(named: "Dismiss", dismiss)
    }
}

struct FleetBlockFoundCelebrationBanner: View {
    let event: MinerBlockFoundEvent
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cube.fill")
                .fleetFont(.title3)
                .foregroundStyle(FleetTheme.accent)
                .frame(width: 40, height: 40)
                .background(FleetTheme.accent.opacity(0.14), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("BLOCK FOUND")
                    .font(FleetTheme.mono(10))
                    .foregroundStyle(FleetTheme.accent)
                Text(event.minerName)
                    .fleetFont(.subheadline, weight: .semibold)
                    .foregroundStyle(FleetTheme.ink)
                Text(
                    [event.coinLabel, event.height.map { "height \(FleetFormat.blockHeight($0))" }]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                )
                .fleetFont(.caption)
                .foregroundStyle(FleetTheme.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Dismiss", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .fleetFont(.caption, weight: .bold)
                .foregroundStyle(FleetTheme.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Dismiss block found notification")
        }
        .padding(FleetSurfaceSpacing.cardInset)
        .background(FleetTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(FleetTheme.accent.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dashboard.blockFoundCelebration")
        .accessibilityLabel(
            "Block found by \(event.minerName)" +
            "\(event.coinLabel.map { ", \($0)" } ?? "")" +
            "\(event.height.map { ", height \(FleetFormat.blockHeight($0))" } ?? "")"
        )
        .accessibilityAction(named: "Dismiss", dismiss)
    }
}

struct DashboardMinerSettingsRoute: Hashable, Identifiable {
    let device: MinerDevice
    let category: MinerSettingsCategory
    var id: String { "\(device.id.uuidString).\(category.rawValue)" }
}

struct FleetHeroCard: View {
    let hashrate: FleetMetricTotal
    /// The proposal shows total draw beside the miner count. It repeats the same reading as the
    /// Total power card rather than deriving a new number, and it stays hidden when unreported.
    let power: FleetMetricTotal
    let onlineCount: Int
    let deviceCount: Int
    let isDemo: Bool
    let isRefreshing: Bool
    let isInitialLoading: Bool
    let realtimeMonitoring: Bool
    let liveConnectionCount: Int
    let liveFallbackCount: Int
    var sourceTitle: String = "SHA-256"
    var compact: Bool = false
    /// Each miner's share of the headline hashrate. Shown only with two or more hashing miners.
    var shareSlices: [FleetHashrateShare.Slice] = []
    @ScaledMetric(relativeTo: .title2) private var valueSize = 32.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(isDemo ? "SAMPLE FLEET HASHRATE" : "FLEET HASHRATE")
                    .fleetFont(.caption2, weight: .semibold, design: .monospaced)
                    .tracking(0.8)
                    .foregroundStyle(FleetTheme.panelAccent)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if !dynamicTypeSize.isAccessibilitySize {
                    FleetLoadAnimatedArt(
                        loop: .fleetCluster,
                        size: CGSize(width: 72, height: 50),
                        accessibilityIdentifier: "dashboard.fleetArtwork"
                    )
                }
            }
            Text(sourceTitle)
                .fleetFont(compact ? .caption2 : .caption, weight: .medium)
                .foregroundStyle(FleetTheme.panelSecondary)
                .accessibilityIdentifier("dashboard.hashrateSource")
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    rateValue
                    rateUnit
                }
                VStack(alignment: .leading, spacing: 4) {
                    rateValue
                    rateUnit
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibleRate)
            .accessibilityIdentifier("dashboard.fleetHashrate")
            if !isInitialLoading, let note = FleetReadingCaption.hashrate(hashrate) {
                Text(note)
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("dashboard.fleetHashrateNote")
            }
            if !isInitialLoading, shareSlices.count >= 2 {
                FleetHashrateShareStrip(slices: shareSlices)
                    .padding(.vertical, compact ? 4 : 6)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        fleetStatus
                        powerStatus
                    }
                    Spacer(minLength: 4)
                    refreshStatus
                }
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        fleetStatus
                        powerStatus
                    }
                    Spacer(minLength: 4)
                    refreshStatus
                }
            }
        }
        .foregroundStyle(FleetTheme.panelInk)
        .fleetCard(padding: compact ? 14 : 18,
                   fill: FleetTheme.charcoal, border: .clear)
    }

    /// A subtotal must never look like a whole-fleet reading, and no reading must never look like
    /// a zero-hashrate fleet. Both cases are stated in words rather than shown as a bare number.
    private var accessibleRate: String {
        if isInitialLoading { return "Loading fleet hashrate" }
        guard hashrate.hasReading else {
            return "Fleet hashrate, not reported\(isDemo ? ", simulated" : "")"
        }
        let base =
            "Fleet hashrate, \(FleetFormat.hashrate(hashrate.value)) \(FleetFormat.hashrateUnit(hashrate.value))"
        let scope =
            hashrate.isPartial ? ", subtotal from \(hashrate.reporting) of \(hashrate.online) online miners" : ""
        return base + ", \(sourceTitle)" + scope + (isDemo ? ", simulated" : "")
    }

    @ViewBuilder
    private var rateValue: some View {
        if isInitialLoading {
            FleetLoadingSkeleton(
                width: 132,
                height: min(valueSize, 90) * 1.2,
                label: "Loading fleet hashrate",
                tint: FleetTheme.panelSecondary
            )
            .accessibilityIdentifier("dashboard.hashrate.loading")
        } else {
            Text(hashrate.hasReading ? FleetFormat.hashrate(hashrate.value) : "—")
                .font(.system(size: min(valueSize, compact ? 72 : 90), weight: .semibold, design: .rounded))
                .tracking(-0.5)
                .monospacedDigit()
                .fleetHeadlineNumericUpdate(
                    hashrate.hasReading ? FleetFormat.hashrate(hashrate.value) : "—",
                    reduceMotion: reduceMotion
                )
        }
    }

    @ViewBuilder
    private var rateUnit: some View {
        if !isInitialLoading, hashrate.hasReading {
            Text(FleetFormat.hashrateUnit(hashrate.value))
                .fleetFont(.title3, design: .monospaced)
                .foregroundStyle(FleetTheme.panelSecondary)
        }
    }

    private var fleetStatus: some View {
        let value = isDemo ? "\(deviceCount) sample miners"
            : (isInitialLoading ? "Connecting to miners…" : "\(onlineCount) of \(deviceCount) online")
        return Label {
            Text(value).fleetNumericUpdate(value, reduceMotion: reduceMotion)
        } icon: {
            Image(systemName: isDemo ? "sparkles" : "circle.fill")
        }
        .fleetFont(.caption, weight: .medium)
        .foregroundStyle(FleetTheme.panelInk)
        .fleetPillPadding()
        .background(FleetTheme.panelInk.opacity(0.07), in: Capsule())
        .accessibilityIdentifier("dashboard.fleetStatus")
    }

    @ViewBuilder
    private var powerStatus: some View {
        if !isInitialLoading, power.hasReading {
            let value = "\(FleetFormat.number(power.value)) W\(power.isPartial ? " subtotal" : "")"
            Label {
                Text(value).fleetNumericUpdate(value, reduceMotion: reduceMotion)
            } icon: {
                Image(systemName: "bolt.fill")
            }
            .fleetFont(.caption, weight: .medium)
            .foregroundStyle(FleetTheme.panelInk)
            .fleetPillPadding()
            .background(FleetTheme.panelInk.opacity(0.07), in: Capsule())
            .accessibilityLabel(
                "\(power.isPartial ? "Reported power subtotal" : "Fleet power"), \(FleetFormat.number(power.value)) watts"
            )
            .accessibilityIdentifier("dashboard.fleetPowerChip")
        }
    }

    private var refreshStatus: some View {
        let presentation = FleetHeroRefreshPresentation.resolve(.init(
            isDemo: isDemo, isInitialLoading: isInitialLoading, isRefreshing: isRefreshing,
            realtimeMonitoring: realtimeMonitoring, liveConnectionCount: liveConnectionCount,
            liveFallbackCount: liveFallbackCount
        ))
        return HStack(spacing: 6) {
            if presentation.showsProgress {
                ProgressView().tint(FleetTheme.panelInk).controlSize(.mini)
            }
            Text(presentation.text)
                .fleetFont(presentation.usesMonospacedCaption ? .caption2 : .caption,
                           design: presentation.usesMonospacedCaption ? .monospaced : .default)
                .accessibilityIdentifier("dashboard.refreshMode")
        }
        .foregroundStyle(FleetTheme.panelSecondary)
    }
}

struct FleetMetricCard: View {
    let title: String
    let value: String
    let unit: String
    let symbol: String
    let caption: String
    let identifier: String
    let accessibleValue: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .fleetFont(.caption2, weight: .medium, design: .monospaced)
                    .tracking(0.8)
                    .foregroundStyle(FleetTheme.secondary)
                Spacer(minLength: 4)
                Image(systemName: symbol)
                    .fleetFont(.caption2)
                    .foregroundStyle(FleetTheme.secondary)
                    .accessibilityHidden(true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    metricValue; metricUnit
                }
                VStack(alignment: .leading, spacing: 4) {
                    metricValue; metricUnit
                }
            }
            Text(caption)
                .fleetFont(.caption)
                .foregroundStyle(FleetTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: FleetLayout.isMac ? .infinity : nil, alignment: .topLeading)
        .fleetCard(padding: FleetSurfaceSpacing.cardInset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(accessibleValue). \(caption)")
        .accessibilityIdentifier(identifier)
    }

    private var metricValue: some View {
        Text(value)
            .fleetFont(.title3, weight: .semibold)
            .monospacedDigit()
            .fleetNumericUpdate(value, reduceMotion: reduceMotion)
    }

    @ViewBuilder
    private var metricUnit: some View {
        if !unit.isEmpty {
            Text(unit).fleetFont(.subheadline, design: .monospaced).foregroundStyle(FleetTheme.secondary)
        }
    }
}

/// Plain-language captions for aggregate readings.
///
/// The rule everywhere: a metric no online miner reported is "Not reported", never a zero, and a
/// metric only some reported is an explicitly labelled subtotal, never a whole-fleet figure.
enum FleetReadingCaption {
    /// Non-nil only when the hero number needs qualifying. A complete reading needs no note.
    static func hashrate(_ reading: FleetMetricTotal) -> String? {
        guard reading.online > 0 else { return nil }
        if !reading.hasReading {
            return "No online miner reported a hashrate. This is not a zero-hashrate fleet."
        }
        guard reading.isPartial else { return nil }
        return
            "Subtotal from \(reading.reporting) of \(reading.online) online miners. " +
                "\(reading.missing) did not report a hashrate."
    }

    static func power(_ reading: FleetMetricTotal) -> String {
        guard reading.online > 0 else { return "No miners online" }
        if !reading.hasReading {
            return "Not reported by any of the \(reading.online) online \(minerWord(reading.online))"
        }
        if reading.isPartial {
            return "Subtotal from \(reading.reporting) of \(reading.online) online miners"
        }
        return "Reported by all \(reading.online) online \(minerWord(reading.online))"
    }

    static func efficiency(_ reading: FleetEfficiencyTotal) -> String {
        guard reading.online > 0 else { return "No miners online" }
        if reading.isPartial {
            return
                "Not reported: only \(reading.reporting) of \(reading.online) online miners " +
                "reported both hashrate and power"
        }
        guard reading.hasReading else {
            return "Needs every online miner to report both hashrate and power"
        }
        return "Power per terahash across all \(reading.online) online \(minerWord(reading.online))"
    }

    private static func minerWord(_ count: Int) -> String { count == 1 ? "miner" : "miners" }
}
