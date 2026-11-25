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
        let canvasColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 2 / 255, green: 9 / 255, blue: 12 / 255, alpha: 1)
                : UIColor(red: 1, green: 1, blue: 1, alpha: 1)
        }
        let separatorColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 39 / 255, green: 52 / 255, blue: 58 / 255, alpha: 1)
                : UIColor(red: 204 / 255, green: 204 / 255, blue: 204 / 255, alpha: 1)
        }
        appearance.backgroundColor = canvasColor.withAlphaComponent(0.55)
        appearance.shadowColor = separatorColor.withAlphaComponent(0.35)

        for item in [appearance.stackedLayoutAppearance,
                     appearance.inlineLayoutAppearance,
                     appearance.compactInlineLayoutAppearance] {
            style(item)
        }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    private static func style(_ item: UITabBarItemAppearance) {
        let accent = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 245 / 255, green: 172 / 255, blue: 38 / 255, alpha: 1)
                : UIColor(red: 138 / 255, green: 80 / 255, blue: 0, alpha: 1)
        }
        let idle = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 191 / 255, green: 198 / 255, blue: 204 / 255, alpha: 1)
                : UIColor(red: 89 / 255, green: 89 / 255, blue: 89 / 255, alpha: 1)
        }

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
