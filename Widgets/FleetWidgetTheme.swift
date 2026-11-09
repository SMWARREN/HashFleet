import HashFleetCore
import SwiftUI
import UIKit
import WidgetKit

/// Widget-specific colors keep the extension independent of the app's UI target.
enum FleetWidgetTheme {
    static let canvas = adaptive(light: 0xFFFFFF, dark: 0x000000)
    static let ink = adaptive(light: 0x21201E, dark: 0xFFFFFF)
    static let secondary = adaptive(light: 0x595959, dark: 0xBDBDBD)
    static let accent = adaptive(light: 0x8A5000, dark: 0xE9931E)
    static let orange = accent

    // Live Activities intentionally use a fixed dark inset, including in light mode.
    static let charcoal = fixed(0x21201E)
    static let raised = fixed(0x373737)
    static let panelInk = fixed(0xFFFFFF)
    static let panelSecondary = fixed(0xBDBDBD)
    static let panelAccent = fixed(0xE9931E)
    static let islandAccent = panelAccent
    static let deepLink = URL(string: "hashfleet://fleet")!

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    private static func fixed(_ value: UInt32) -> Color {
        Color(uiColor: UIColor(hex: value))
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

struct FleetWidgetBrand: View {
    var isActivity = false

    var body: some View {
        HStack(spacing: 6) {
            FleetWidgetBrandMark(monochrome: isActivity)
                .foregroundStyle(isActivity ? FleetWidgetTheme.panelAccent : FleetWidgetTheme.accent)
                .fleetWidgetAccentable(role: .brandLogo)
            Text(FleetWidgetBrandAssets.displayName)
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .tracking(1)
                .foregroundStyle(isActivity ? FleetWidgetTheme.panelInk : FleetWidgetTheme.ink)
        }
        .accessibilityLabel("Hash Fleet")
    }
}

struct FleetWidgetTimestamp: View {
    let date: Date
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .accessibilityHidden(true)
            if compact {
                Text(date, style: .time)
            } else {
                Text(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
            }
        }
        .font(.system(.caption2, design: .monospaced))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityLabel("Updated \(date.formatted(date: .abbreviated, time: .shortened))")
    }
}

/// Keep custom VoiceOver summaries from bypassing system privacy redaction.
/// Protect the full data surface, including counts and update times, not just
/// the large hashrate value. Empty onboarding remains readable.
struct FleetWidgetPrivacy: ViewModifier {
    let presentation: FleetGlancePresentation
    @Environment(\.redactionReasons) private var redactionReasons

    func body(content: Content) -> some View {
        content
            // Ignored children can remain inspectable in the raw accessibility tree.
            // Replace that tree with only the appropriate summary, not private metric labels.
            // The Refresh action stays a separate sibling outside this representation.
            .accessibilityRepresentation {
                Text(redactionReasons.isEmpty || !presentation.hasMiners
                    ? presentation.accessibilitySummary
                    : presentation.redactedAccessibilitySummary)
                    .accessibilityHint("Open Hash Fleet")
            }
            .privacySensitive(presentation.hasMiners)
    }
}

/// Safe helper extension to adopt accented/tinted rendering mode semantics
/// cleanly with backward compatibility for iOS 17.
extension View {
    @ViewBuilder
    func fleetWidgetAccentable(role: FleetWidgetAppearancePolicy.ElementRole) -> some View {
        if FleetWidgetAppearancePolicy.isAccentable(role: role) {
            self.widgetAccentable(true)
        } else {
            self.widgetAccentable(false)
        }
    }
}

extension Image {
    @ViewBuilder
    func fleetAccentedArtwork() -> some View {
        if #available(iOS 18.0, *) {
            self.widgetAccentedRenderingMode(.accentedDesaturated)
        } else {
            self
        }
    }
}
