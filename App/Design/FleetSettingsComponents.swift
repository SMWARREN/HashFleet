import SwiftUI
import HashFleetCore

struct FleetPrimaryButtonStyle: ButtonStyle {
    enum Tone: CaseIterable { case accent, darkPanel, secondary }
    enum Size { case compact, comfortable }

    struct Palette {
        let ink: Color
        let fill: Color

        static func resolve(_ tone: Tone, isEnabled: Bool) -> Self {
            guard isEnabled else {
                return Self(ink: FleetTheme.secondary, fill: FleetTheme.surface)
            }
            switch tone {
            case .accent:
                return Self(ink: FleetTheme.buttonInk, fill: FleetTheme.accent)
            case .darkPanel:
                return Self(ink: FleetTheme.charcoal, fill: FleetTheme.panelAccent)
            case .secondary:
                return Self(ink: FleetTheme.ink, fill: FleetTheme.raised)
            }
        }
    }

    var tone: Tone = .accent
    var size: Size = .comfortable
    var fullWidth = false
    @Environment(\.isEnabled) private var isEnabled

    /// Keep native button semantics, but choose text and fill together rather than letting
    /// the current system's prominent style choose the foreground from the ambient tint.
    func makeBody(configuration: Configuration) -> some View {
        let palette = Palette.resolve(tone, isEnabled: isEnabled)
        let comfortable = size == .comfortable
        let shape = RoundedRectangle(cornerRadius: comfortable ? 18 : 12)
        configuration.label
            .fleetFont(comfortable ? .headline : .subheadline, weight: .semibold)
            .symbolRenderingMode(.monochrome)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, comfortable ? 20 : 12)
            .padding(.vertical, comfortable ? 16 : 6)
            .frame(minWidth: 44, maxWidth: fullWidth || comfortable ? .infinity : nil,
                   minHeight: comfortable ? 56 : 44)
            .foregroundStyle(palette.ink)
            .tint(palette.ink)
            .background(palette.fill, in: shape)
            .overlay {
                if !isEnabled {
                    shape.strokeBorder(FleetTheme.controlBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                } else if configuration.isPressed {
                    shape.inset(by: 2).strokeBorder(palette.ink, lineWidth: 2)
                } else if tone == .secondary {
                    shape.strokeBorder(FleetTheme.controlBorder)
                }
            }
            .contentShape(Rectangle())
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

/// Retain the idle label's size so an active button does not jump during a save.
struct FleetPendingButtonLabel: View {
    let title: String
    let pendingTitle: String
    let isPending: Bool

    var body: some View {
        ZStack {
            Text(title).opacity(isPending ? 0 : 1)
            if isPending {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).accessibilityHidden(true)
                    Text(pendingTitle)
                }
            }
        }
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
                }
                Text(isLoading ? "Working…" : title)
            }
            .fleetFont(.headline)
        }
            .buttonStyle(FleetPrimaryButtonStyle(size: .compact, fullWidth: true))
            .padding(.top, 5)
            .disabled(isLoading)
            .accessibilityValue(isLoading ? "In progress" : "Ready")
    }
}
