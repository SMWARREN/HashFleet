import SwiftUI
import WidgetKit

struct FleetInlineWidget: View {
    let presentation: FleetGlancePresentation

    var body: some View {
        if !presentation.hasMiners {
            Label {
                Text("Hash Fleet · Open app to connect")
            } icon: {
                Image(FleetWidgetBrandAssets.templateName, bundle: FleetWidgetBrandAssets.bundle)
                    .renderingMode(.template)
            }
        } else if presentation.glance.isDemo {
            let msg = "Demo\(presentation.isStale ? " stale" : "") \u{00B7}"
                + " \(presentation.rate) \(presentation.rateUnit) \u{00B7} "
            Text(msg) + Text(presentation.glance.updatedAt, style: .time)
        } else if presentation.isStale {
            Text("Hash Fleet cached \u{00B7} ")
                + Text(presentation.glance.updatedAt, style: .time)
                + Text(" \u{00B7} open app to refresh")
        } else {
            Text("Hash Fleet \(presentation.rate) \(presentation.rateUnit) · \(presentation.glance.updatedAt, style: .time)")
        }
    }
}

struct FleetCircularWidget: View {
    let presentation: FleetGlancePresentation

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 2) {
                FleetWidgetBrandMark(size: 14, monochrome: true)
                if presentation.hasMiners {
                    let stale = presentation.isStale
                    let text = presentation.glance.isDemo
                        ? (stale ? "DEMO OLD" : "DEMO")
                        : (stale ? "STALE" : "FLEET")
                    Text(text)
                        .font(.caption2.weight(.semibold))
                        .fleetWidgetAccentable(role: .badge)
                        .lineLimit(1)
                    Text(presentation.isStale ? "—" : "\(presentation.rate) \(presentation.rateUnit)")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .minimumScaleFactor(0.65)
                        .fleetWidgetAccentable(role: .primaryMetric)
                        .lineLimit(1)
                        .privacySensitive()
                } else {
                    Text("Open app")
                        .font(.caption2.weight(.semibold))
                        .fleetWidgetAccentable(role: .badge)
                }
            }
            .padding(5)
        }
    }
}

struct FleetRectangularWidget: View {
    let presentation: FleetGlancePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if presentation.hasMiners {
                let msg = presentation.glance.isDemo
                    ? "Hash Fleet \u{00B7} \(presentation.badge)"
                    : "Hash Fleet\(presentation.isStale ? " \u{00B7} STALE" : "")"
                Text(msg)
                    .font(.caption.weight(.semibold))
                    .fleetWidgetAccentable(role: .badge)
                    .lineLimit(1)
                Text("\(presentation.rate) \(presentation.rateUnit)\(presentation.isStale ? " cached" : "")")
                    .font(.headline)
                    .monospacedDigit()
                    .fleetWidgetAccentable(role: .primaryMetric)
                    .privacySensitive()
                    .lineLimit(1)
                FleetWidgetTimestamp(date: presentation.glance.updatedAt, compact: true)
            } else {
                HStack(spacing: 5) {
                    FleetWidgetBrandMark(size: 16, monochrome: true)
                    Text(FleetWidgetBrandAssets.displayName)
                }
                    .font(.headline)
                    .fleetWidgetAccentable(role: .brandLogo)
                Text("Open app to connect a miner")
                    .font(.caption)
                    .lineLimit(2)
            }
        }
    }
}
