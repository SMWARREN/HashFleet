import SwiftUI

enum FleetSupportRoute: Hashable {
    case page
}

/// A discoverable internal page, not an automatic payment redirect.
struct DeveloperSupportView: View {
    @State private var availability: DeveloperSupportAvailability
    @State private var tipJarService: DeveloperTipJarService?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fleetStandalonePage) private var standalonePage

    init(availability: DeveloperSupportAvailability = .init()) {
        _availability = State(initialValue: availability)
        if availability.usesNativeTipJar {
            _tipJarService = State(initialValue: DeveloperTipJarService.shared)
        } else {
            _tipJarService = State(initialValue: nil)
        }
    }

    var body: some View {
        FleetSettingsList {
            FleetSettingsIntroduction(
                title: "Independent. Open source. Community supported.",
                message: "Thank you for helping keep Hash Fleet free. Support is always optional, and your miners and notifications work the same whether you tip or not.",
                identifier: "support.introduction"
            ) {
                Image(systemName: "heart")
                    .fleetFont(.title, weight: .semibold)
                    .foregroundStyle(FleetTheme.accent)
                    .accessibilityHidden(true)
            }
            if let tipJarService {
                DeveloperTipJarSection(service: tipJarService)
            }
            DeveloperSupportSection(showsUnavailableMessage: availability.directDistribution, availability: availability)
        }
        .fleetFont(.body)
        .scrollContentBackground(.hidden)
        .background(FleetTheme.canvas)
        .tint(FleetTheme.accent)
        .navigationTitle("Support Hash Fleet")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("support.page")
        .toolbar {
            if !standalonePage {
                ToolbarItem(placement: FleetToolbarLocation.trailing) {
                    Button("Done") { dismiss() }
                        .fleetToolbarButton()
                        .foregroundStyle(FleetTheme.accent)
                        .accessibilityIdentifier("support.done")
                }
                .fleetUnadornedToolbarBackground()
            }
        }
        // Loading belongs to the page, not an offscreen lazy settings section.
        .task(id: scenePhase) {
            await availability.observe(while: scenePhase)
        }
        .fleetPerformanceScreen("Support")
    }
}
