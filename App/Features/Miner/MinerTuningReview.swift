import SwiftUI

/// The same guarded apply action in two presentations. Easy keeps the review and acknowledgement
/// together; Advanced retains the full payload card. Neither presentation owns a write path.
struct MinerTuningReview: View {
    let mode: MinerTuningControlMode
    let summary: String
    let stagedJSON: String?
    @Binding var riskAcknowledged: Bool
    let isBeyondReference: Bool
    let voltageRestriction: String?
    let isDemo: Bool
    let isOffline: Bool
    let isApplying: Bool
    let canApply: Bool
    let error: String?
    let statusMessage: String?
    let onReview: () -> Void

    var body: some View {
        Group {
            if mode == .easy {
                MinerControlsCard { reviewContent }
            } else {
                reviewContent.fleetCard(padding: FleetSurfaceSpacing.cardInset, fill: FleetTheme.surface)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(mode == .easy ? "tuningSession.easyReview" : "tuningSession.review")
    }

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if mode == .easy {
                easyReview
            } else {
                Label("One settings update", systemImage: "curlybraces.square.fill")
                    .fleetFont(.headline)
                Text("The exact JSON stays here. One review flow covers the tuning change without a second screen.")
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
                MinerTuningPayloadView(stagedJSON: stagedJSON)
            }
            feedback
            Button(action: onReview) {
                HStack {
                    Label(isApplying ? "Applying…" : "Apply tuning change", systemImage: "checkmark.shield.fill")
                    Spacer(minLength: 8)
                    if isApplying { ProgressView().controlSize(.small) }
                }
                .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canApply)
            .accessibilityIdentifier("tuningSession.apply")
            if mode == .advanced {
                Text(isDemo ? "Demo mode shows the payload but never writes."
                     : "One confirmation sends the payload, refreshes current readings and records the result below.")
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var easyReview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summary)
                .fleetFont(.subheadline, weight: .semibold)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("tuningSession.changeSummary")
            if let voltageRestriction {
                Label(voltageRestriction, systemImage: "lock.shield.fill")
                    .fleetFont(.caption, weight: .semibold)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("tuningSession.voltageRestriction")
            } else if isBeyondReference {
                Label("Above firmware reference. Extra heat, power and hardware risk.", systemImage: "exclamationmark.octagon.fill")
                    .fleetFont(.caption, weight: .semibold)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("tuningSession.overReferenceWarning")
            }
            Text("Changes can increase heat and power and damage hardware. Reported choices are not safety guarantees.")
                .fleetFont(.caption)
                .foregroundStyle(FleetTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("I understand the hardware risks", isOn: $riskAcknowledged)
                .fleetFont(.subheadline)
                .disabled(isApplying)
                .accessibilityIdentifier("tuningSession.riskAcknowledgement")
            if isDemo || isOffline {
                Label(isDemo ? "Demo · no changes are sent" : "Read only · reconnect to apply", systemImage: "lock.fill")
                    .fleetFont(.caption)
                    .foregroundStyle(FleetTheme.warning)
                    .accessibilityIdentifier("tuningSession.writeRestriction")
            }
        }
    }

    @ViewBuilder private var feedback: some View {
        if let error {
            Text(error)
                .fleetFont(.footnote)
                .foregroundStyle(FleetTheme.warning)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("tuningSession.error")
        }
        if let statusMessage {
            Label(statusMessage, systemImage: "checkmark.circle.fill")
                .fleetFont(.footnote, weight: .semibold)
                .foregroundStyle(FleetTheme.positive)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("tuningSession.status")
        }
    }
}

struct MinerTuningPayloadView: View {
    let stagedJSON: String?

    var body: some View {
        if let stagedJSON {
            Text(stagedJSON)
                .fleetFont(.caption, design: .monospaced)
                .foregroundStyle(FleetTheme.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(FleetSurfaceSpacing.cardInset)
                .background(FleetTheme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("tuningSession.payload")
        } else {
            Text("Change a value to stage a valid firmware payload.")
                .fleetFont(.caption)
                .foregroundStyle(FleetTheme.secondary)
                .accessibilityIdentifier("tuningSession.payloadUnavailable")
        }
    }
}
