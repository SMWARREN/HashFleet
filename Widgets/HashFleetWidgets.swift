import SwiftUI
import WidgetKit

@main
struct HashFleetWidgets: WidgetBundle {
    var body: some Widget {
        FleetWidget()
        FleetLiveActivityWidget()
        if #available(iOS 18.0, *) {
            FleetControlWidget()
        }
    }
}
