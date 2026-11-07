import AppIntents
import SwiftUI
import WidgetKit

/// iOS 18 Control Center and Lock Screen control. It only invokes the shared open-fleet intent.
/// Control widgets are surfaced through public WidgetKit APIs and do not require a separate
/// capability or signup flow. No UIApplication access is used from this extension.
@available(iOS 18.0, *)
struct FleetControlWidget: ControlWidget {
    private static let kind = "app.hashfleet.control.open-fleet"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenFleetIntent()) {
                Label {
                    Text("Open Hash Fleet")
                } icon: {
                    Image(FleetWidgetBrandAssets.templateName, bundle: FleetWidgetBrandAssets.bundle)
                        .renderingMode(.template)
                }
            }
            .tint(.orange)
        }
        .displayName("Open Hash Fleet")
        .description("Open Hash Fleet's fleet dashboard.")
    }
}
