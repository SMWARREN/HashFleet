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
    var numberFirst: Bool = false
    @ScaledMetric(relativeTo: .title2) private var valueSize = 38.0
    @ScaledMetric(relativeTo: .largeTitle) private var numberFirstSize = 44.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if numberFirst {
            numberFirstContent
        } else {
            panelContent
        }
    }

    private var numberFirstContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            heroHeading
            if let note = FleetReadingCaption.hashrate(hashrate) {
                Text(note)
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("dashboard.fleetHashrateNote")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    sourceLabel
                    powerStatus
                }
                .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 6) {
                    sourceLabel
                    powerStatus
                }
            }
            .foregroundStyle(FleetTheme.panelSecondary)
        }
        .foregroundStyle(FleetTheme.panelInk)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fleetCard(padding: compact ? 14 : 18, fill: FleetTheme.charcoal, border: .clear)
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            heroHeading
            if !isInitialLoading, let note = FleetReadingCaption.hashrate(hashrate) {
                Text(note)
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("dashboard.fleetHashrateNote")
            }
            Rectangle()
                .fill(FleetTheme.panelSecondary.opacity(0.35))
                .frame(height: 1)
                .accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    fleetStatus
                    powerStatus
                    Spacer(minLength: 0)
                    refreshStatus
                }
                .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 6) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            fleetStatus
                            powerStatus
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 6) {
                            fleetStatus
                            powerStatus
                        }
                    }
                    refreshStatus
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(FleetTheme.panelInk)
        .fleetCard(padding: compact ? 16 : 18,
                   fill: FleetTheme.charcoal, border: .clear)
    }

    private var heroHeading: some View {
        HStack(alignment: .top, spacing: 8) {
            headline
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 0)
                FleetLoadAnimatedArt(
                    loop: .fleetCluster,
                    size: CGSize(width: 72, height: 50),
                    accessibilityIdentifier: "dashboard.fleetArtwork"
                )
            }
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: numberFirst ? 2 : 4) {
            Text(isDemo && !numberFirst ? "Sample fleet hashrate" : "Fleet hashrate")
                .fleetFont(numberFirst ? .subheadline : .headline, weight: numberFirst ? .semibold : nil)
                .foregroundStyle(FleetTheme.panelAccent)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !numberFirst { sourceLabel }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
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
        }
    }

    private var sourceLabel: some View {
        Text(sourceTitle)
            .fleetFont(numberFirst ? .caption : .footnote, weight: .medium)
            .foregroundStyle(FleetTheme.panelSecondary)
            .accessibilityIdentifier("dashboard.hashrateSource")
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
        } else if hashrate.hasReading {
            let value = FleetFormat.hashrate(hashrate.value)
            Text(value)
                .font(.system(size: numberFirst ? min(numberFirstSize, 48) : min(valueSize, compact ? 80 : 90),
                              weight: numberFirst ? .bold : .semibold, design: numberFirst ? .default : .rounded))
                .monospacedDigit()
                .fleetHeadlineNumericUpdate(value, reduceMotion: reduceMotion)
        } else {
            Text("Not reported")
                .fleetFont(.title3, weight: .semibold)
        }
    }

    @ViewBuilder
    private var rateUnit: some View {
        if !isInitialLoading, hashrate.hasReading {
            Text(FleetFormat.hashrateUnit(hashrate.value))
                .fleetFont(numberFirst ? .callout : .title3, weight: .medium)
                .foregroundStyle(FleetTheme.panelSecondary)
        }
    }

    private var fleetStatus: some View {
        let value = isDemo ? "\(deviceCount) sample miners"
            : (isInitialLoading ? "Connecting to miners…" : "\(onlineCount) of \(deviceCount) online")
        return Label {
            Text(value).fleetNumericUpdate(value, reduceMotion: reduceMotion)
        } icon: {
            Image(systemName: isDemo ? "sparkles" : "circle.grid.2x2")
                .accessibilityHidden(true)
        }
        .fleetFont(.footnote, weight: .semibold)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("dashboard.fleetStatus")
    }

    @ViewBuilder
    private var powerStatus: some View {
        if !isInitialLoading, power.hasReading {
            let value = "\(FleetFormat.number(power.value)) W\(power.isPartial ? " subtotal" : "")"
            let text = numberFirst ? "Power: \(value)" : value
            Label {
                Text(text).fleetNumericUpdate(value, reduceMotion: reduceMotion)
            } icon: {
                Image(systemName: "bolt")
                    .accessibilityHidden(true)
            }
            .fleetFont(numberFirst ? .caption : .footnote, weight: .semibold)
            .fixedSize(horizontal: false, vertical: true)
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
                .fleetFont(.footnote)
                .fixedSize(horizontal: false, vertical: true)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .fleetFont(.headline)
                    .foregroundStyle(FleetTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Image(systemName: symbol)
                    .fleetFont(.subheadline)
                    .foregroundStyle(FleetTheme.secondary)
                    .accessibilityHidden(true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    metricValue
                    metricUnit
                }
                VStack(alignment: .leading, spacing: 4) {
                    metricValue
                    metricUnit
                }
            }
            Text(caption)
                .fleetFont(.footnote)
                .foregroundStyle(FleetTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: FleetLayout.isMac ? .infinity : nil, alignment: .topLeading)
        .fleetCard(padding: FleetSurfaceSpacing.cardInset, border: FleetTheme.separator)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(accessibleValue). \(caption)")
        .accessibilityIdentifier(identifier)
    }

    private var metricValue: some View {
        Text(value)
            .fleetFont(.title2, weight: .semibold)
            .monospacedDigit()
            .fleetNumericUpdate(value, reduceMotion: reduceMotion)
    }

    @ViewBuilder
    private var metricUnit: some View {
        if !unit.isEmpty {
            Text(unit).fleetFont(.subheadline, weight: .medium).foregroundStyle(FleetTheme.secondary)
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
