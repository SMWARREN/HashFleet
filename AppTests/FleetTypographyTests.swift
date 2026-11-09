import SwiftUI
import UIKit
import Testing
@testable import HashFleet

@Suite("Shared reading typography")
struct FleetTypographyTests {
    @MainActor
    @Test func nativeRoleCurvesMatchTheCurrentIPadMetrics() {
        let roles: [(Font.TextStyle, UIFont.TextStyle)] = [
            (.largeTitle, .largeTitle), (.title, .title1), (.title2, .title2),
            (.title3, .title3), (.headline, .headline), (.body, .body),
            (.callout, .callout), (.subheadline, .subheadline),
            (.footnote, .footnote), (.caption, .caption1), (.caption2, .caption2)
        ]
        let categories: [UIContentSizeCategory] = [
            .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge,
            .extraExtraExtraLarge, .accessibilityMedium, .accessibilityLarge,
            .accessibilityExtraLarge, .accessibilityExtraExtraLarge,
            .accessibilityExtraExtraExtraLarge
        ]

        for (style, nativeStyle) in roles {
            for (size, nativeSize) in zip(FleetTypography.categories, categories) {
                let expected = UIFont.preferredFont(
                    forTextStyle: nativeStyle,
                    compatibleWith: UITraitCollection(preferredContentSizeCategory: nativeSize)
                ).pointSize
                #expect(FleetTypography.pointSize(for: style, category: size) == expected)
            }
        }
    }

    @Test func displayRolesUseApprovedDefaultPointSizes() {
        #expect(FleetTypography.displayPointSize(for: .hero32, category: .large) == 32)
        #expect(FleetTypography.displayPointSize(for: .large44, category: .large) == 44)
        #expect(FleetTypography.displayPointSize(for: .extraLarge64, category: .large) == 64)
    }

    @Test func displayRolesScaleAlongTheSharedTitle2AccessibilityCurve() {
        let roles: [(FleetDisplayFontRole, CGFloat)] = [
            (.hero32, 32),
            (.large44, 44),
            (.extraLarge64, 64)
        ]

        for (role, baseline) in roles {
            let standard = FleetTypography.displayPointSize(for: role, category: .large)
            let extraLarge = FleetTypography.displayPointSize(for: role, category: .xLarge)
            let accessibility1 = FleetTypography.displayPointSize(for: role, category: .accessibility1)
            let accessibility5 = FleetTypography.displayPointSize(for: role, category: .accessibility5)

            #expect(standard == baseline)
            #expect(extraLarge > standard)
            #expect(accessibility1 > extraLarge)
            #expect(accessibility5 > accessibility1)
        }
    }

    @Test func semanticFontRoleWeightsRemainDistinct() {
        #expect(FleetTypography.defaultWeight(for: .headline) == .semibold)
        #expect(FleetTypography.defaultWeight(for: .body) == .regular)
        #expect(FleetTypography.defaultWeight(for: .caption) == .regular)
    }
}
