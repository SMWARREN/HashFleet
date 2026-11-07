import HashFleetCore
import SwiftUI

/// Keeps custom drafts in their own navigation scope, separate from trusted native forms.
struct MinerCustomJSONRoute: View {
    let device: MinerDevice
    let store: FleetStore
    let insights: MiningInsightsStore?
    @State private var staged: CustomJSONReviewDraft?

    private var isOffline: Bool {
        !store.isDemo && !MinerWriteAvailability.allows(store.snapshot(for: device.id))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: MinerSnapshotFreshness.refreshInterval)) { _ in
            MinerCustomJSONView(device: device, isDemo: store.isDemo, isOffline: isOffline) { json in
                staged = CustomJSONReviewDraft(json: json)
            }
        }
        .navigationDestination(item: $staged) { draft in
            MinerEndpointView(
                device: device,
                store: store,
                endpoint: .settings,
                initialJSON: draft.json,
                insights: insights
            )
        }
    }
}

#Preview("Custom JSON · demo") {
    let store = FleetStore(defaults: UserDefaults(suiteName: "app.hashfleet.json-route-preview")!)
    store.loadDemo()
    return NavigationStack {
        MinerCustomJSONRoute(device: store.devices[0], store: store, insights: nil)
    }
}

private struct CustomJSONReviewDraft: Hashable {
    let id = UUID()
    let json: String
}
