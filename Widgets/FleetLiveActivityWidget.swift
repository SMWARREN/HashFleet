import ActivityKit
import SwiftUI
import WidgetKit

struct FleetLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        let activityConfig = ActivityConfiguration(for: FleetActivityAttributes.self) { context in
            FleetLockScreenActivity(presentation: presentation(for: context))
                .activityBackgroundTint(FleetWidgetTheme.charcoal)
                .activitySystemActionForegroundColor(FleetWidgetTheme.islandAccent)
                .widgetURL(FleetWidgetTheme.deepLink)
        } dynamicIsland: { context in
            let snapshot = presentation(for: context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    FleetWidgetBrand(isActivity: true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(snapshot.badge)
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .foregroundStyle(FleetWidgetTheme.islandAccent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .privacySensitive(snapshot.hasMiners)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    FleetExpandedActivity(presentation: snapshot)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    FleetWidgetBrandMark(size: 18, monochrome: true)
                    if snapshot.glance.isDemo {
                        Text("DEMO").font(.caption2.weight(.semibold))
                    }
                }
                .foregroundStyle(FleetWidgetTheme.islandAccent)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    snapshot.glance.isDemo
                        ? "Demo sample fleet"
                        : (snapshot.isStale ? "Stale fleet snapshot" : "Hash Fleet")
                )
                .privacySensitive(snapshot.hasMiners)
            } compactTrailing: {
                if snapshot.hasMiners {
                    VStack(spacing: 0) {
                        Text(snapshot.isStale ? "STALE" : "\(snapshot.rate) \(snapshot.rateUnit)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .privacySensitive()
                        Text(snapshot.glance.updatedAt, style: .time)
                            .font(.caption2.monospaced())
                            .foregroundStyle(FleetWidgetTheme.panelSecondary)
                            .lineLimit(1)
                    }
                    .foregroundStyle(FleetWidgetTheme.panelInk)
                    .modifier(FleetWidgetPrivacy(presentation: snapshot))
                } else {
                    Text("OPEN").font(.caption2.weight(.semibold))
                        .foregroundStyle(FleetWidgetTheme.panelInk)
                        .accessibilityLabel("Open Hash Fleet to connect a miner")
                }
            } minimal: {
                if snapshot.glance.isDemo {
                    Text("DEMO")
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(FleetWidgetTheme.islandAccent)
                        .accessibilityLabel("Hash Fleet demo sample\(snapshot.isStale ? ", stale" : "")")
                        .privacySensitive(snapshot.hasMiners)
                } else {
                    HStack(spacing: 0) {
                        FleetWidgetBrandMark(size: 18, monochrome: true)
                    }
                        .foregroundStyle(FleetWidgetTheme.islandAccent)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            snapshot.hasMiners
                                ? (snapshot.isStale
                                   ? "Hash Fleet stale snapshot"
                                   : "Hash Fleet cached snapshot")
                                : "Open Hash Fleet to connect"
                        )
                        .privacySensitive(snapshot.hasMiners)
                }
            }
            .widgetURL(FleetWidgetTheme.deepLink)
            .keylineTint(FleetWidgetTheme.islandAccent)
        }

        if #available(iOS 18.0, *) {
            return activityConfig.supplementalActivityFamilies([.small])
        } else {
            return activityConfig
        }
    }

    private func presentation(for context: ActivityViewContext<FleetActivityAttributes>) -> FleetGlancePresentation {
        FleetGlancePresentation(
            glance: context.state.glance,
            isStale: context.isStale || context.state.glance.isStale(at: Date())
        )
    }
}

private struct FleetLockScreenActivity: View {
    let presentation: FleetGlancePresentation

    var body: some View {
        if #available(iOS 18.0, *) {
            FleetAdaptiveLockScreenActivity(presentation: presentation)
        } else {
            FleetStandardLockScreenActivity(presentation: presentation)
        }
    }
}

@available(iOS 18.0, *)
private struct FleetAdaptiveLockScreenActivity: View {
    let presentation: FleetGlancePresentation
    @Environment(\.activityFamily) private var activityFamily

    var body: some View {
        if activityFamily == .small {
            FleetSmallSupplementalActivity(presentation: presentation)
        } else {
            FleetStandardLockScreenActivity(presentation: presentation)
        }
    }
}

/// Small supplemental presentation for supported devices (e.g. Apple Watch Smart Stack mirroring).
struct FleetSmallSupplementalActivity: View {
    let presentation: FleetGlancePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                FleetWidgetBrand(isActivity: true)
                Spacer(minLength: 0)
                Text(presentation.badge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(FleetWidgetTheme.islandAccent)
                    .lineLimit(1)
            }
            if presentation.hasMiners {
                Text("\(presentation.rate) \(presentation.rateUnit)")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .privacySensitive()
                Text(presentation.status)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(FleetWidgetTheme.panelSecondary)
            } else {
                Text("Open app to connect")
                    .font(.caption)
                    .foregroundStyle(FleetWidgetTheme.islandAccent)
            }
        }
        .padding(10)
        .foregroundStyle(FleetWidgetTheme.panelInk)
        .modifier(FleetWidgetPrivacy(presentation: presentation))
    }
}

struct FleetStandardLockScreenActivity: View {
    let presentation: FleetGlancePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                FleetWidgetBrand(isActivity: true)
                Spacer(minLength: 0)
                Text(presentation.badge)
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(FleetWidgetTheme.islandAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            if presentation.hasMiners {
                FleetActivityMetrics(presentation: presentation)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(presentation.status)
                        .font(.caption)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    FleetWidgetTimestamp(date: presentation.glance.updatedAt, compact: true)
                }
                .foregroundStyle(FleetWidgetTheme.panelSecondary)
            } else {
                Text("Your fleet starts in Hash Fleet.")
                    .font(.headline)
                Label("Open the app to connect a miner", systemImage: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(FleetWidgetTheme.islandAccent)
            }
        }
        .padding(16)
        .foregroundStyle(FleetWidgetTheme.panelInk)
        .modifier(FleetWidgetPrivacy(presentation: presentation))
    }
}

struct FleetExpandedActivity: View {
    let presentation: FleetGlancePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if presentation.hasMiners {
                FleetActivityMetrics(presentation: presentation)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(presentation.status)
                        .font(.caption2)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    FleetWidgetTimestamp(date: presentation.glance.updatedAt, compact: true)
                }
                .foregroundStyle(FleetWidgetTheme.panelSecondary)
            } else {
                Label("Open Hash Fleet to connect your first miner", systemImage: "arrow.up.right")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FleetWidgetTheme.islandAccent)
            }
        }
        .padding(.top, 6)
        .modifier(FleetWidgetPrivacy(presentation: presentation))
    }
}

struct FleetActivityMetrics: View {
    let presentation: FleetGlancePresentation

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.rateLabel)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(FleetWidgetTheme.panelSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(presentation.rate)
                        .font(.system(.title, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                    Text(presentation.rateUnit)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(FleetWidgetTheme.panelSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Label("POWER", systemImage: "bolt")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(FleetWidgetTheme.panelSecondary)
                Text("\(presentation.power) W")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .foregroundStyle(FleetWidgetTheme.panelInk)
        .privacySensitive()
    }
}
