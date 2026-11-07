import Foundation
import SwiftUI
import UIKit
import WidgetKit

/// The framework test host and the production extension resolve the same compiled assets.
enum FleetWidgetBrandAssets {
    private final class ResourceToken: NSObject {}
    static let bundle = Bundle(for: ResourceToken.self)
    static let colorName = "HashFleetWidgetBrand"
    static let templateName = "HashFleetWidgetTemplate"
    static let displayName = "Hash Fleet"
    static let maximumPixelDimension: CGFloat = 256

    static func assetName(monochrome: Bool) -> String {
        monochrome ? templateName : colorName
    }

    @MainActor
    static func thumbnail(
        monochrome: Bool, colorScheme: ColorScheme, pointSize: CGFloat, displayScale: CGFloat
    ) -> UIImage? {
        guard pointSize.isFinite, pointSize > 0, displayScale.isFinite, displayScale > 0 else { return nil }
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        guard let source = UIImage(named: assetName(monochrome: monochrome), in: bundle, compatibleWith: traits) else {
            return nil
        }
        // A view frame does not reduce the image archived by WidgetKit. Keep the approved
        // source artwork, but archive only the pixels needed by this small mark.
        let dimension = min(maximumPixelDimension, max(1, ceil(pointSize * displayScale)))
        let bounds = CGRect(x: 0, y: 0, width: dimension, height: dimension)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: bounds.size, format: format).image { _ in
            source.withRenderingMode(.alwaysOriginal).draw(in: bounds)
        }
    }
}

struct FleetWidgetBrandMark: View {
    var size: CGFloat = 18
    var monochrome = false
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let isTemplate = monochrome || renderingMode != .fullColor
        Group {
            if let image = FleetWidgetBrandAssets.thumbnail(
                monochrome: isTemplate, colorScheme: colorScheme, pointSize: size, displayScale: displayScale
            ) {
                Image(uiImage: image)
                    .renderingMode(isTemplate ? .template : .original)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .widgetAccentable(isTemplate)
        .accessibilityHidden(true)
    }
}
