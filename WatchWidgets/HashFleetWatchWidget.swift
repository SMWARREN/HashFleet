import SwiftUI
import WidgetKit

/// A quick way into the independent Watch app, not a background mining monitor.
@main
struct HashFleetWatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HashFleet.OpenWatch", provider: WatchLauncherProvider()) { _ in
            WatchLauncherView()
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Open Hash Fleet")
        .description("Open your miners quickly from the Smart Stack or your watch face.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}
