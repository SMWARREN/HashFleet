import SwiftUI
import WidgetKit

struct WatchLauncherView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var accent: Color {
        renderingMode == .fullColor ? Color(red: 1, green: 0.79, blue: 0.22) : .primary
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "cpu")
                        .font(.title2)
                        .foregroundStyle(accent)
                        .widgetAccentable()
                }
            case .accessoryInline:
                Label("Hash Fleet", systemImage: "cpu")
            default:
                HStack(spacing: 8) {
                    Image(systemName: "cpu")
                        .font(.title2)
                        .foregroundStyle(accent)
                        .widgetAccentable()
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
