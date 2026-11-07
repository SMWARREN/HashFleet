import SwiftUI
import WidgetKit
import AppIntents
import HashFleetCore

struct FleetWidgetRefreshPresentation: Equatable, Sendable {
    let isEnabled: Bool
    let message: String?
    var isRefreshing = false

    func invalidated(_ isInvalidated: Bool) -> Self {
        guard isEnabled, isRefreshing || isInvalidated else { return self }
        return Self(isEnabled: true, message: "Refreshing…", isRefreshing: true)
    }
}

struct FleetWidgetEntry: TimelineEntry {
    let date: Date
    let glance: FleetGlance
    var refresh: FleetWidgetRefreshPresentation?

    var presentation: FleetGlancePresentation {
        FleetGlancePresentation(glance: glance, isStale: glance.isStale(at: max(date, Date())),
            refreshMessage: refresh?.message)
    }
}

struct FleetWidgetProvider: TimelineProvider, Sendable {
    private let storage: FleetGlanceStorage
    private let refreshStorage: FleetWidgetRefreshStorage
    private let read: FleetWidgetRefreshRunner.Read
    private let now: @Sendable () -> Date
    static let automaticReloadInterval: TimeInterval = 5 * 60

    init(storage: FleetGlanceStorage = .shared, refreshStorage: FleetWidgetRefreshStorage = .init(directory: nil),
         read: @escaping FleetWidgetRefreshRunner.Read = { try await FleetScheduledCheckReader().read($0) },
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.storage = storage
        self.refreshStorage = refreshStorage
        self.read = read
        self.now = now
    }

    func placeholder(in context: Context) -> FleetWidgetEntry {
        FleetWidgetEntry(date: Date(), glance: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (FleetWidgetEntry) -> Void) {
        completion(snapshot(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<FleetWidgetEntry>) -> Void) {
        let isPreview = context.isPreview
        Task {
            completion(await automaticTimeline(isPreview: isPreview))
        }
    }

    /// WidgetKit owns when this runs. Preview/snapshot rendering never grants network access.
    func automaticTimeline(isPreview: Bool = false) async -> Timeline<FleetWidgetEntry> {
        let date = now()
        let saved = storage.load()
        if !isPreview, !saved.isDemo, let state = refreshStorage.load(),
           state.configuration.isEnabled(at: date), state.configuration.automaticRefreshGeneration != nil,
           saved.minerCount == 0 || saved.minerCount == state.configuration.targets.count,
           entry(at: date, saved: saved, refreshed: state).glance.isStale(at: date) {
            // Await the real, identity-checked read and atomic persistence before returning entries.
            // This does not invoke an AppIntent or pretend to wake the containing app.
            _ = await FleetWidgetRefreshRunner(storage: refreshStorage, read: read, now: now)
                .refresh(automatically: true)
        }
        return timeline(at: now())
    }

    func snapshot(at date: Date) -> FleetWidgetEntry {
        entry(at: date, saved: storage.load(), refreshed: refreshStorage.load())
    }

    func timeline(at now: Date) -> Timeline<FleetWidgetEntry> {
        let saved = storage.load()
        let refreshed = refreshStorage.load()
        let first = entry(at: now, saved: saved, refreshed: refreshed)
        let glance = first.glance
        var dates = [now]
        // Rendering alone never changes an observation time. getTimeline separately awaits a read.
        let staleAt = glance.updatedAt.addingTimeInterval(FleetGlance.freshnessInterval)
        if glance.minerCount > 0, staleAt > now, !glance.isStale(at: now) {
            dates.append(staleAt)
        }
        if let expires = refreshed?.configuration.expiresAt, expires > now, expires < now.addingTimeInterval(15 * 60) {
            dates.append(expires)
        }
        // A provider execution during an intent must not archive an endless loading state.
        if let expires = refreshed?.lease?.expiresAt, expires > now {
            dates.append(expires)
        }
        let entries = Set(dates).sorted().map { entry(at: $0, saved: saved, refreshed: refreshed) }
        let automatic = !saved.isDemo && first.refresh?.isEnabled == true
            && refreshed?.configuration.automaticRefreshGeneration != nil
        let interval = automatic ? Self.automaticReloadInterval : 15 * 60
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(interval)))
    }

    private func entry(at date: Date, saved: FleetGlance, refreshed: FleetWidgetRefreshState?) -> FleetWidgetEntry {
        // Never relabel Demo, mix inventories or advance an observation timestamp during rendering.
        guard !saved.isDemo, let refreshed else { return FleetWidgetEntry(date: date, glance: saved) }
        let sameInventorySize = saved.minerCount == 0 || saved.minerCount == refreshed.configuration.targets.count
        let enabled = sameInventorySize && refreshed.configuration.isEnabled(at: date)
        var glance = saved
        // Permission expiry disables new reads, not the last valid observation already saved.
        if sameInventorySize, let candidate = refreshed.glance, candidate.isValid, !candidate.isDemo,
           candidate.minerCount == refreshed.configuration.targets.count,
           saved.minerCount == 0 || saved.minerCount == candidate.minerCount,
           candidate.updatedAt <= date.addingTimeInterval(5),
           saved.minerCount == 0 || candidate.updatedAt > saved.updatedAt {
            glance = candidate
        }
        let waitingForAutomatic = enabled && refreshed.configuration.automaticRefreshGeneration != nil
            && glance.isStale(at: date)
        let refreshing = enabled && refreshed.lease.map { $0.startedAt <= date && date < $0.expiresAt } == true
        let expiredLease = enabled && refreshed.lease.map { date >= $0.expiresAt } == true
        let message = enabled
            ? (refreshing ? "Refreshing…" : expiredLease ? FleetWidgetRefreshOutcome.timedOut.widgetMessage
                : refreshed.lastOutcome?.widgetMessage ?? (waitingForAutomatic ? "Auto refresh · waiting for iOS" : nil))
            : FleetWidgetRefreshOutcome.needsSetup.widgetMessage
        return FleetWidgetEntry(date: date, glance: glance,
            refresh: .init(isEnabled: enabled, message: message, isRefreshing: refreshing))
    }
}

struct FleetWidget: Widget {
    let kind = "HashFleet.Fleet"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FleetWidgetProvider(refreshStorage: .shared)) { entry in
            FleetWidgetView(entry: entry)
                .widgetURL(FleetWidgetTheme.deepLink)
                .containerBackground(FleetWidgetTheme.canvas, for: .widget)
        }
        .configurationDisplayName("Fleet at a glance")
        .description(
            "Saved fleet readings with optional read-only local refresh."
            + " Readings older than a minute are marked stale."
        )
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular
        ])
        .contentMarginsDisabled()
    }
}

struct FleetWidgetView: View {
    let entry: FleetWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        FleetWidgetContent(entry: entry, family: family)
            // WidgetKit supplies .invalidated immediately after a tap until the new timeline arrives.
            // Local @State and an on-tap Task cannot drive an archived widget's loading UI.
            .invalidatableContent()
    }
}

/// Explicit family input lets the same production content be rendered without faking a get-only environment value.
struct FleetWidgetContent: View {
    let entry: FleetWidgetEntry
    let family: WidgetFamily
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        let refresh = entry.refresh?.invalidated(redactionReasons.contains(.invalidated))
        Group {
            switch family {
            case .accessoryInline:
                FleetInlineWidget(presentation: entry.presentation)
            case .accessoryCircular:
                FleetCircularWidget(presentation: entry.presentation)
            case .accessoryRectangular:
                FleetRectangularWidget(presentation: entry.presentation)
            case .systemMedium:
                FleetMediumWidget(presentation: entry.presentation, renderingMode: renderingMode, refresh: refresh)
            case .systemLarge:
                FleetLargeWidget(presentation: entry.presentation, renderingMode: renderingMode, refresh: refresh)
            default:
                FleetSmallWidget(presentation: entry.presentation, renderingMode: renderingMode, refresh: refresh)
            }
        }
        .modifier(FleetWidgetPrivacy(presentation: entry.presentation))
        // Keep this sibling outside the privacy summary's children:.ignore, so VoiceOver can
        // reach the action without exposing redacted aggregate text. The header reserves its slot.
        .overlay(alignment: .topTrailing) {
            if [.systemSmall, .systemMedium, .systemLarge].contains(family), let refresh {
                FleetWidgetRefreshButton(presentation: refresh)
                    .padding(.trailing, family == .systemLarge ? 16 : 14)
                    .padding(.top, family == .systemLarge ? 6 : 4)
            }
        }
    }
}

struct FleetSmallWidget: View {
    let presentation: FleetGlancePresentation
    let renderingMode: WidgetRenderingMode
    var refresh: FleetWidgetRefreshPresentation?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                FleetWidgetBrand()
                if refresh != nil {
                    Spacer(minLength: 0)
                    Color.clear.frame(width: 44, height: 24).accessibilityHidden(true)
                }
            }
            Spacer(minLength: 2)
            if presentation.hasMiners {
                Text(presentation.badge)
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(renderingMode == .accented ? Color.primary : FleetWidgetTheme.orange)
                    .fleetWidgetAccentable(role: .badge)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(presentation.rate)
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .fleetWidgetAccentable(role: .primaryMetric)
                    Text(presentation.rateUnit)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(FleetWidgetTheme.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .privacySensitive()
                Text(refresh?.message ?? presentation.status)
                    .font(.caption2)
                    .lineLimit(2)
                    .foregroundStyle(FleetWidgetTheme.secondary)
                Spacer(minLength: 0)
                FleetWidgetTimestamp(date: presentation.glance.updatedAt)
                    .foregroundStyle(FleetWidgetTheme.secondary)
            } else {
                Text("A little fleet.\nA lot of possibility.")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Label("Open app to connect", systemImage: "arrow.up.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(renderingMode == .accented ? Color.primary : FleetWidgetTheme.orange)
                    .fleetWidgetAccentable(role: .badge)
            }
        }
        .foregroundStyle(FleetWidgetTheme.ink)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct FleetMediumWidget: View {
    let presentation: FleetGlancePresentation
    let renderingMode: WidgetRenderingMode
    var refresh: FleetWidgetRefreshPresentation?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                FleetWidgetBrand()
                Spacer(minLength: 8)
                Text(presentation.badge)
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(renderingMode == .accented ? Color.primary : FleetWidgetTheme.orange)
                    .fleetWidgetAccentable(role: .badge)
                    .lineLimit(1)
                if refresh != nil { Color.clear.frame(width: 44, height: 24).accessibilityHidden(true) }
            }
            if presentation.hasMiners {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(presentation.rateLabel)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(FleetWidgetTheme.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(presentation.rate)
                                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                                .monospacedDigit()
                                .fleetWidgetAccentable(role: .primaryMetric)
                            Text(presentation.rateUnit)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(FleetWidgetTheme.secondary)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 6) {
                        Label("POWER", systemImage: "bolt")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(FleetWidgetTheme.secondary)
                        Text("\(presentation.power)\u{2002}W")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        let msg = presentation.glance.isDemo
                            ? "sample miners online"
                            : "miners online"
                        Text(
                            "\(presentation.glance.onlineCount)/"
                            + "\(presentation.glance.minerCount) \(msg)"
                        )
                            .font(.caption2)
                            .foregroundStyle(FleetWidgetTheme.secondary)
                            .lineLimit(1)
                    }
                }
                .privacySensitive()
                Spacer(minLength: 0)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(refresh?.message ?? presentation.status)
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        FleetWidgetTimestamp(date: presentation.glance.updatedAt, compact: true)
                            .fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(refresh?.message ?? presentation.status)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        FleetWidgetTimestamp(date: presentation.glance.updatedAt, compact: true)
                    }
                }
                .font(.caption2)
                .foregroundStyle(FleetWidgetTheme.secondary)
            } else {
                HStack(spacing: 18) {
                    FleetWidgetBrandMark(size: 52)
                        .foregroundStyle(renderingMode == .accented ? Color.primary : FleetWidgetTheme.orange)
                        .fleetWidgetAccentable(role: .brandLogo)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your fleet starts in Hash Fleet.")
                            .font(.headline)
                        Text("Open the app to connect a miner and save your first snapshot.")
                            .font(.caption)
                            .foregroundStyle(FleetWidgetTheme.secondary)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .foregroundStyle(FleetWidgetTheme.ink)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// SystemLarge widget adopting pure aggregate metrics (hashrate, power, online count, derived efficiency).
/// No fabricated individual miners or speculative charts: strictly aggregate figures.
struct FleetLargeWidget: View {
    let presentation: FleetGlancePresentation
    let renderingMode: WidgetRenderingMode
    var refresh: FleetWidgetRefreshPresentation?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                FleetWidgetBrand()
                Spacer(minLength: 8)
                Text(presentation.badge)
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(renderingMode == .accented ? Color.primary : FleetWidgetTheme.orange)
                    .fleetWidgetAccentable(role: .badge)
                    .lineLimit(1)
                if refresh != nil { Color.clear.frame(width: 44, height: 24).accessibilityHidden(true) }
            }

            if presentation.hasMiners {
                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.rateLabel)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(FleetWidgetTheme.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(presentation.rate)
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .fleetWidgetAccentable(role: .primaryMetric)
                        Text(presentation.rateUnit)
                            .font(.system(.subheadline, design: .monospaced).weight(.medium))
                            .foregroundStyle(FleetWidgetTheme.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
                .privacySensitive()

                Divider()

                // Key aggregate telemetry grid
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("FLEET POWER", systemImage: "bolt")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(FleetWidgetTheme.secondary)
                        Text("\(presentation.power)\u{2002}W")
                            .font(.system(.title2, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let efficiency = presentation.efficiencyJPerTH {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("EFFICIENCY", systemImage: "leaf")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(FleetWidgetTheme.secondary)
                            Text("\(efficiency) J/TH")
                                .font(.system(.title2, design: .rounded).weight(.semibold))
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .privacySensitive()

                VStack(alignment: .leading, spacing: 6) {
                    Label("ONLINE STATUS", systemImage: "server.rack")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(FleetWidgetTheme.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(presentation.glance.onlineCount) of \(presentation.glance.minerCount)")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                        Text(presentation.glance.isDemo ? "sample miners" : "miners active")
                            .font(.system(.subheadline))
                            .foregroundStyle(FleetWidgetTheme.secondary)
                    }
                    .lineLimit(1)
                }
                .privacySensitive()

                Spacer(minLength: 0)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(refresh?.message ?? presentation.status)
                        .font(.caption2)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    FleetWidgetTimestamp(date: presentation.glance.updatedAt, compact: false)
                }
                .foregroundStyle(FleetWidgetTheme.secondary)
            } else {
                VStack(alignment: .center, spacing: 16) {
                    Spacer()
                    FleetWidgetBrandMark(size: 72)
                        .foregroundStyle(renderingMode == .accented ? Color.primary : FleetWidgetTheme.orange)
                        .fleetWidgetAccentable(role: .brandLogo)
                    VStack(spacing: 6) {
                        Text("Your fleet starts in Hash Fleet.")
                            .font(.title3.weight(.medium))
                        Text("Open the app to connect a miner and save your first snapshot.")
                            .font(.caption)
                            .foregroundStyle(FleetWidgetTheme.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    Spacer()
                    Label("Open app to connect", systemImage: "arrow.up.right")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(renderingMode == .accented ? Color.primary : FleetWidgetTheme.orange)
                        .fleetWidgetAccentable(role: .badge)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(FleetWidgetTheme.ink)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct FleetWidgetRefreshButton: View {
    let presentation: FleetWidgetRefreshPresentation

    var body: some View {
        Group {
            if presentation.isEnabled {
                Button(intent: RefreshFleetWidgetIntent()) {
                    Group {
                        if presentation.isRefreshing {
                            // Indeterminate circular ProgressView becomes an empty capacity gauge
                            // in widgets. Archive an explicit activity ring instead of a blank spinner.
                            Circle()
                                .trim(from: 0.12, to: 0.85)
                                .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(presentation.isRefreshing)
                .accessibilityLabel(presentation.isRefreshing ? "Refreshing fleet" : "Refresh fleet")
                .accessibilityHint(presentation.isRefreshing
                    ? "Reading local miners. The saved reading stays visible until this finishes."
                    : presentation.message ?? "Requires unlock and the miners' local network. Read only.")
                .accessibilityIdentifier("widget.refresh")
            } else {
                Link(destination: FleetWidgetTheme.deepLink) {
                    Image(systemName: "arrow.up.right")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Open Hash Fleet to prepare refresh")
                .accessibilityIdentifier("widget.prepareRefresh")
            }
        }
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(FleetWidgetTheme.orange)
        .fleetWidgetAccentable(role: .badge)
    }
}
