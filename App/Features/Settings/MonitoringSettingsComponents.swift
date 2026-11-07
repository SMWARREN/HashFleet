import SwiftUI

/// The proposals present short explanatory guarantees as icon-plus-text cards rather than plain
/// footnotes. This carries no action, so VoiceOver reads it as a single static label.
struct MonitoringNoteRow: View {
    let symbol: String
    var title: String?
    let message: String
    var tint: Color = FleetTheme.secondary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .fleetFont(.headline)
                .foregroundStyle(tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                if let title {
                    Text(title).fleetFont(.subheadline, weight: .semibold).foregroundStyle(tint)
                }
                Text(message)
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct MonitoringErrorAlert: ViewModifier {
    @Bindable var coordinator: FleetGlanceCoordinator

    func body(content: Content) -> some View {
        content.alert(
            "Monitoring",
            isPresented: Binding(
                get: { coordinator.error != nil },
                set: { if !$0 { coordinator.error = nil } }
            )
        ) {
            Button("OK") { coordinator.error = nil }
        } message: {
            Text(coordinator.error ?? "")
        }
    }
}
