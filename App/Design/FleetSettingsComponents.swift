import SwiftUI
import HashFleetCore

struct FleetPrimaryButtonStyle: ButtonStyle {
    var onDarkSurface = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fleetFont(.headline)
            .frame(maxWidth: .infinity, minHeight: 24)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .foregroundStyle(onDarkSurface ? Color.black : FleetTheme.buttonInk)
            .background(onDarkSurface ? FleetTheme.panelAccent : FleetTheme.accent,
                        in: RoundedRectangle(cornerRadius: 18))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// The app keeps this alias for existing feature files while the implementation lives in HashFleetCore.
typealias FleetFormat = HashFleetCore.FleetFormat

/// App-only difficulty adapters. The base numeric and sensor formatters live in HashFleetCore
/// so the CLI, widgets, Mac companion, and iOS app share the same presentation rules.
extension HashFleetCore.FleetFormat {
    static func difficulty(_ value: Double?) -> String {
        MiningDifficultyFormat.short(value) ?? "Not reported"
    }

    static func difficulty(_ value: String?) -> String {
        MiningDifficultyFormat.short(value) ?? "Not reported"
    }

    static func difficulty(_ value: JSONValue?) -> String {
        MiningDifficultyFormat.short(value) ?? "Not reported"
    }
}

/// Card container used by the 2026 page redesign for grouped settings controls.
/// Replaces a `Form` `Section` on screens that render inside a `ScrollView`,
/// so the same grouping reads consistently across settings categories.
struct FleetSettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(FleetSurfaceSpacing.cardInset)
            .background(
                LinearGradient(colors: [FleetTheme.surface, FleetTheme.raised.opacity(0.72)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(FleetTheme.controlBorder.opacity(0.55)))
    }
}

/// Title row for a `FleetSettingsCard`, standing in for a section header.
struct FleetSettingsCardHeader: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).fleetFont(.title3).foregroundStyle(FleetTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fleetFont(.headline).foregroundStyle(FleetTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle).fleetFont(.caption).foregroundStyle(FleetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Full-width review button. Every write still passes through the existing
/// review and confirmation flow; this only styles the entry point.
struct FleetReviewButton: View {
    let title: String
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(FleetTheme.buttonInk)
                }
                Text(isLoading ? "Working…" : title)
            }
            .fleetFont(.headline)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
            .buttonStyle(.borderedProminent)
            .tint(FleetTheme.accent)
            .foregroundStyle(FleetTheme.buttonInk)
            .frame(maxWidth: .infinity)
            .padding(.top, 5)
            .disabled(isLoading)
            .accessibilityValue(isLoading ? "In progress" : "Ready")
    }
}
