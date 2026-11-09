import SwiftUI

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Tab bar styling shared by every scene.
///
/// The proposal boards show a floating capsule with a quiet, evenly weighted icon set: the
/// selected tab reads through an amber label and a soft tinted pill, not a heavier glyph. UIKit
/// still owns the tab bar chrome, so the appearance is configured once at launch rather than with
/// per-view modifiers that only affect a single screen.
@MainActor
enum FleetTabBarAppearance {
#if canImport(UIKit)
    static func apply() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        // The canvas already provides the page colour. A faint wash keeps the capsule legible over
        // scrolled content without turning into an opaque slab.
        appearance.backgroundColor = UIColor(FleetTheme.canvas).withAlphaComponent(0.55)
        appearance.shadowColor = UIColor(FleetTheme.separator).withAlphaComponent(0.35)

        for item in [appearance.stackedLayoutAppearance,
                     appearance.inlineLayoutAppearance,
                     appearance.compactInlineLayoutAppearance] {
            style(item)
        }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    private static func style(_ item: UITabBarItemAppearance) {
        let accent = UIColor(FleetTheme.accent)
        let idle = UIColor(FleetTheme.secondary)

        item.normal.iconColor = idle
        item.normal.titleTextAttributes = [
            .foregroundColor: idle,
            .font: UIFont.systemFont(ofSize: 10, weight: .medium),
            .kern: 0.2
        ]

        item.selected.iconColor = accent
        item.selected.titleTextAttributes = [
            .foregroundColor: accent,
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
            .kern: 0.2
        ]
    }
#else
    @MainActor
    static func apply() {
        // Native macOS: tab bar appearance is handled by SwiftUI tabViewStyle or AppKit
        // No-op on macOS; iOS-specific appearance is configured separately
    }
#endif
}
