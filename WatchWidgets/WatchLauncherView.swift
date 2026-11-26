import SwiftUI
import UIKit
import WidgetKit

struct WatchLauncherView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var isTemplate: Bool {
        renderingMode != .fullColor
    }

    /// WatchKit's WidgetKit archiver rejects images larger than the watch screen area.
    /// The shared brand assets are 1254x1254 px, so downsample to a crisp complication size.
    private func downsampledBrandImage(named name: String, pixelSize: Int = 96) -> UIImage? {
        guard let source = UIImage(named: name)?.cgImage,
              let context = CGContext(
                  data: nil,
                  width: pixelSize,
                  height: pixelSize,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        guard let scaled = context.makeImage() else { return nil }
        return UIImage(cgImage: scaled)
    }

    @ViewBuilder
    private var brandImage: some View {
        let assetName = isTemplate ? "HashFleetWidgetTemplate" : "HashFleetWidgetBrand"
        Group {
            if let thumbnail = downsampledBrandImage(named: assetName) {
                Image(uiImage: thumbnail)
                    .renderingMode(isTemplate ? .template : .original)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(assetName)
                    .renderingMode(isTemplate ? .template : .original)
                    .resizable()
                    .scaledToFit()
            }
        }
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
