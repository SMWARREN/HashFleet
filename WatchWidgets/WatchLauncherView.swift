import SwiftUI
import WidgetKit

struct WatchLauncherView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var isTemplate: Bool {
        renderingMode != .fullColor
    }

    @ViewBuilder
    private var brandImage: some View {
        Image(isTemplate ? "HashFleetWidgetTemplate" : "HashFleetWidgetBrand")
            .renderingMode(isTemplate ? .template : .original)
            .resizable()
            .scaledToFit()
            .widgetAccentable(isTemplate)
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    brandImage
                        .padding(4)
                }
            case .accessoryCorner:
                brandImage
                    .padding(2)
            case .accessoryInline:
                Label("Hash Fleet", systemImage: "bolt.fill")
            default:
                HStack(spacing: 8) {
                    brandImage
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hash Fleet")
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text("Open miners")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        // WidgetKit's default interaction opens the containing Watch app. No URL,
        // App Intent, iPhone handoff or shared miner-data container is required.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Open Hash Fleet")
        .accessibilityHint("View your miners and refresh their readings.")
        .accessibilityIdentifier("watch.widget.launch")
    }
}
