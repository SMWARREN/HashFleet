import SwiftUI

/// Shared reading roles, using the familiar iPad baseline on the native Mac too.
/// Native semantic defaults are smaller (body 13, subheadline 11), so inheriting
/// them beside our shared artwork and sidebar produces two conflicting scales.
enum FleetTypography {
    // Captured from UIFont.preferredFont on the iPad simulator on October 25, 2026.
    // macOS ScaledMetric did not grow at accessibility3 in the render regression.
    // Keep each role's curve rather than inventing a global text/view multiplier.
    static let categories: [DynamicTypeSize] = [
        .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
        .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5
    ]

    static func pointSize(
        for style: Font.TextStyle,
        category: DynamicTypeSize = .large
    ) -> CGFloat {
        let sizes: [CGFloat]
        switch style {
        case .largeTitle: sizes = [31, 32, 33, 34, 36, 38, 40, 44, 48, 52, 56, 60]
        case .title: sizes = [25, 26, 27, 28, 30, 32, 34, 38, 43, 48, 53, 58]
        case .title2: sizes = [19, 20, 21, 22, 24, 26, 28, 34, 39, 44, 50, 56]
        case .title3: sizes = [17, 18, 19, 20, 22, 24, 26, 31, 37, 43, 49, 55]
        case .headline, .body: sizes = [14, 15, 16, 17, 19, 21, 23, 28, 33, 40, 47, 53]
        case .callout: sizes = [13, 14, 15, 16, 18, 20, 22, 26, 32, 38, 44, 51]
        case .subheadline: sizes = [12, 13, 14, 15, 17, 19, 21, 25, 30, 36, 42, 49]
        case .footnote: sizes = [12, 12, 12, 13, 15, 17, 19, 23, 27, 33, 38, 44]
        case .caption: sizes = [11, 11, 11, 12, 14, 16, 18, 22, 26, 32, 37, 43]
        case .caption2: sizes = [11, 11, 11, 11, 13, 15, 17, 20, 24, 29, 34, 40]
        @unknown default: sizes = [14, 15, 16, 17, 19, 21, 23, 28, 33, 40, 47, 53]
        }
        return sizes[categories.firstIndex(of: category) ?? 3]
    }

    static func displayPointSize(
        for role: FleetDisplayFontRole,
        category: DynamicTypeSize = .large
    ) -> CGFloat {
        role.baselineSize * pointSize(for: .title2, category: category) / 22
    }

    static func defaultWeight(for style: Font.TextStyle) -> Font.Weight {
        style == .headline ? .semibold : .regular
    }
}

enum FleetDisplayFontRole: Sendable {
    case hero32
    case large44
    case extraLarge64

    var baselineSize: CGFloat {
        switch self {
        case .hero32: 32
        case .large44: 44
        case .extraLarge64: 64
        }
    }
}

extension View {
    /// Retains iOS semantic fonts and the current accessibility environment.
    /// The Mac uses role-specific baselines, not a view transform or a forced
    /// Dynamic Type category. Each requested category retains its measured role curve.
    func fleetFont(
        _ style: Font.TextStyle,
        weight: Font.Weight? = nil,
        design: Font.Design = .default
    ) -> some View {
        modifier(FleetSemanticFontModifier(style: style, weight: weight, design: design))
    }

    func fleetDisplayFont(
        role: FleetDisplayFontRole = .hero32,
        weight: Font.Weight = .bold,
        design: Font.Design = .rounded
    ) -> some View {
        modifier(FleetDisplayFontModifier(role: role, weight: weight, design: design))
    }
}

private struct FleetSemanticFontModifier: ViewModifier {
    let style: Font.TextStyle
    let weight: Font.Weight?
    let design: Font.Design
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(style: Font.TextStyle, weight: Font.Weight?, design: Font.Design) {
        self.style = style
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        #if os(macOS)
        content.font(.system(
            size: FleetTypography.pointSize(for: style, category: dynamicTypeSize),
            weight: weight ?? FleetTypography.defaultWeight(for: style),
            design: design
        ))
        #else
        content.font(.system(style, design: design, weight: weight))
        #endif
    }
}

private struct FleetDisplayFontModifier: ViewModifier {
    let role: FleetDisplayFontRole
    let weight: Font.Weight
    let design: Font.Design
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.font(.system(
            size: FleetTypography.displayPointSize(for: role, category: dynamicTypeSize),
            weight: weight,
            design: design
        ))
    }
}
