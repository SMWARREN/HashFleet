import Foundation
import SwiftUI
import UIKit
import Testing
import HashFleetCore
@testable import HashFleet

@Suite(.serialized) @MainActor
struct FleetPreferencesTests {
    @Test func dashboardCoinSelectionPersistsAndEmptyIsNotAutomatic() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = FleetPreferences(defaults: defaults)
        #expect(preferences.dashboardCoins == nil)
        preferences.dashboardCoins = [.btc, .dgb]
        #expect(FleetPreferences(defaults: defaults).dashboardCoins == [.btc, .dgb])
        preferences.dashboardCoins = []
        #expect(FleetPreferences(defaults: defaults).dashboardCoins == [])
        preferences.dashboardCoins = nil
        #expect(defaults.object(forKey: FleetPreferences.Keys.dashboardCoins) == nil)
        #expect(FleetPreferences(defaults: defaults).dashboardCoins == nil)
        defaults.set(["btc", "btc", "unknown"], forKey: FleetPreferences.Keys.dashboardCoins)
        #expect(FleetPreferences(defaults: defaults).dashboardCoins == [.btc])
        defaults.set("invalid", forKey: FleetPreferences.Keys.dashboardCoins)
        #expect(FleetPreferences(defaults: defaults).dashboardCoins == nil)
        #expect(preferences.realtimeMonitoring == FleetPreferences.defaultRealtimeMonitoring)
        #expect(preferences.blockNotificationsEnabled == false)
        #expect(preferences.bestShareNotificationsEnabled)
        #expect(preferences.sessionBestNotificationsEnabled)
    }

    @Test func telemetryRetentionPersistsAndMalformedValuesFallBackWithoutCrashing() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        // Missing key uses the default.
        #expect(FleetPreferences(defaults: defaults).telemetryRetention
            == FleetPreferences.defaultTelemetryRetention)

        // A valid stored value round-trips.
        var preferences = FleetPreferences(defaults: defaults)
        preferences.telemetryRetention = .quarter
        #expect(FleetPreferences(defaults: defaults).telemetryRetention == .quarter)

        // A raw value outside the enum falls back instead of pinning a nonsense retention.
        defaults.set(999_999, forKey: FleetPreferences.Keys.telemetryRetention)
        #expect(FleetPreferences(defaults: defaults).telemetryRetention
            == FleetPreferences.defaultTelemetryRetention)

        // A non-integer value (corrupted plist / foreign writer) must not crash launch.
        defaults.set("forever-ish", forKey: FleetPreferences.Keys.telemetryRetention)
        #expect(FleetPreferences(defaults: defaults).telemetryRetention
            == FleetPreferences.defaultTelemetryRetention)

        // Writing again clears the malformed value with a valid one.
        preferences = FleetPreferences(defaults: defaults)
        preferences.telemetryRetention = .week
        #expect(FleetPreferences(defaults: defaults).telemetryRetention == .week)
    }

    func makeSuite() throws -> (UserDefaults, String) {
        let suite = "app.hashfleet.preferences.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (defaults, suite)
    }

    private struct ColorRoleExpectation: Sendable {
        let color: Color
        let lightHex: UInt32
        let darkHex: UInt32
    }

    private static let colorRoles: [ColorRoleExpectation] = [
        .init(color: FleetTheme.canvas, lightHex: 0xFFFFFF, darkHex: 0x02090C),
        .init(color: FleetTheme.surface, lightHex: 0xF5F5F5, darkHex: 0x10191D),
        .init(color: FleetTheme.raised, lightHex: 0xE5E5E5, darkHex: 0x182126),
        .init(color: FleetTheme.ink, lightHex: 0x21201E, darkHex: 0xF4F6F7),
        .init(color: FleetTheme.secondary, lightHex: 0x595959, darkHex: 0xBFC6CC),
        .init(color: FleetTheme.accent, lightHex: 0x8A5000, darkHex: 0xF5AC26),
        .init(color: FleetTheme.charcoal, lightHex: 0x111111, darkHex: 0x111111),
        .init(color: FleetTheme.soloSurface, lightHex: 0x21201E, darkHex: 0x21201E),
        .init(color: FleetTheme.panelInk, lightHex: 0xFFFFFF, darkHex: 0xF4F6F7),
        .init(color: FleetTheme.panelSecondary, lightHex: 0xBDBDBD, darkHex: 0xBFC6CC),
        .init(color: FleetTheme.panelPositive, lightHex: 0x2AAE68, darkHex: 0x25A354),
        .init(color: FleetTheme.panelAccent, lightHex: 0xE9931E, darkHex: 0xF5AC26),
        .init(color: FleetTheme.hashrateSurface, lightHex: 0x111111, darkHex: 0xF5F5F5),
        .init(color: FleetTheme.hashrateInk, lightHex: 0xFFFFFF, darkHex: 0x111111),
        .init(color: FleetTheme.hashrateSecondary, lightHex: 0xBDBDBD, darkHex: 0x595959),
        .init(color: FleetTheme.hashrateAccent, lightHex: 0xE9931E, darkHex: 0x8A5000),
        .init(color: FleetTheme.hashrateSkeleton, lightHex: 0x262626, darkHex: 0xE0E0E0),
        .init(color: FleetTheme.marqueeSurface, lightHex: 0xFFFFFF, darkHex: 0x02090C),
        .init(color: FleetTheme.marqueeInk, lightHex: 0x21201E, darkHex: 0xF4F6F7),
        .init(color: FleetTheme.marqueeSecondary, lightHex: 0x595959, darkHex: 0xBFC6CC),
        .init(color: FleetTheme.comparisonBorder, lightHex: 0xE9931E, darkHex: 0xFFB72E),
        .init(color: FleetTheme.positive, lightHex: 0x356447, darkHex: 0x25A354),
        .init(color: FleetTheme.warning, lightHex: 0x864705, darkHex: 0xF5AC26),
        .init(color: FleetTheme.separator, lightHex: 0xCCCCCC, darkHex: 0x27343A),
        .init(color: FleetTheme.controlBorder, lightHex: 0x897869, darkHex: 0x566F7C),
        .init(color: FleetTheme.chartFourth, lightHex: 0x897869, darkHex: 0xC6CED6),
        .init(color: FleetTheme.buttonInk, lightHex: 0xFFFFFF, darkHex: 0x10120F)
    ]

    private static func rgb(_ color: Color, style: UIUserInterfaceStyle) throws -> [Double] {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        #expect(resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        #expect(alpha == 1)
        return [Double(red), Double(green), Double(blue)]
    }

    private static func hex(_ color: Color, style: UIUserInterfaceStyle) throws -> UInt32 {
        let components = try rgb(color, style: style)
        return UInt32(
            components.enumerated().reduce(0) { result, component in
                result | UInt32((component.element * 255).rounded()) << UInt32((2 - component.offset) * 8)
            }
        )
    }

    private static func luminance(_ components: [Double]) -> Double {
        let linear = components.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
    }

    private static func contrast(
        _ foreground: Color, _ background: Color, style: UIUserInterfaceStyle
    ) throws -> Double {
        let foregroundLuminance = luminance(try rgb(foreground, style: style))
        let backgroundLuminance = luminance(try rgb(background, style: style))
        return (max(foregroundLuminance, backgroundLuminance) + 0.05)
            / (min(foregroundLuminance, backgroundLuminance) + 0.05)
    }

    func makeOnlineSnapshot(
        hashrate: Double = 1000,
        power: Double = 20,
        temp: Double = 55,
        sharesAccepted: Int = 150,
        uptimeSeconds: Int = 3600,
        version: String = "v2.1.0"
    ) -> MinerSnapshot {
        let raw: [String: JSONValue] = [
            "hashRate": .number(hashrate),
            "power": .number(power),
            "temp": .number(temp),
            "sharesAccepted": .number(Double(sharesAccepted)),
            "uptimeSeconds": .number(Double(uptimeSeconds)),
            "version": .string(version)
        ]
        return MinerSnapshot(info: MinerInfo(raw: raw), error: nil, updatedAt: Date(), history: [])
    }

    func makeOfflineSnapshot(error: String = "Connection refused") -> MinerSnapshot {
        MinerSnapshot(info: nil, error: error, updatedAt: Date(), history: [])
    }

    // MARK: - Persistence

    @Test func appearanceColorsMatchValidatedRolesAndContrast() throws {

        for style in [UIUserInterfaceStyle.light, .dark] {
            for role in Self.colorRoles {
                let color = role.color
                let lightHex = role.lightHex
                let darkHex = role.darkHex
                #expect(try Self.hex(color, style: style) == (style == .dark ? darkHex : lightHex))
            }

            // Latest request explicitly replaces the no-white/no-black restriction.
            #expect(try Self.hex(FleetTheme.canvas, style: style) == (style == .light ? 0xFFFFFF : 0x02090C))
            #expect(try Self.hex(FleetTheme.surface, style: style) != Self.hex(FleetTheme.canvas, style: style))
            #expect(try Self.hex(FleetTheme.raised, style: style) != Self.hex(FleetTheme.surface, style: style))
            #expect(try Self.hex(FleetTheme.raised, style: style) != Self.hex(FleetTheme.canvas, style: style))

            for text in [
                FleetTheme.ink,
                FleetTheme.secondary,
                FleetTheme.accent,
                FleetTheme.positive,
                FleetTheme.warning
            ] {
                for background in [FleetTheme.canvas, FleetTheme.surface, FleetTheme.raised] {
                    #expect(try Self.contrast(text, background, style: style) >= 4.5)
                }
            }

            for (text, background) in [
                (FleetTheme.marqueeInk, FleetTheme.marqueeSurface),
                (FleetTheme.marqueeSecondary, FleetTheme.marqueeSurface),
                (FleetTheme.positive, FleetTheme.marqueeSurface),
                (FleetTheme.warning, FleetTheme.marqueeSurface),
                (FleetTheme.panelPositive, FleetTheme.charcoal),
                (FleetTheme.panelInk, FleetTheme.charcoal),
                (FleetTheme.panelSecondary, FleetTheme.charcoal),
                (FleetTheme.panelAccent, FleetTheme.charcoal),
                (FleetTheme.panelInk, FleetTheme.soloSurface),
                (FleetTheme.panelSecondary, FleetTheme.soloSurface),
                (FleetTheme.panelAccent, FleetTheme.soloSurface),
                (FleetTheme.panelPositive, FleetTheme.soloSurface),
                (FleetTheme.buttonInk, FleetTheme.accent),
                (FleetTheme.hashrateSecondary, FleetTheme.hashrateSurface),
                (FleetTheme.hashrateAccent, FleetTheme.hashrateSurface)
            ] {
                #expect(try Self.contrast(text, background, style: style) >= 4.5)
            }

            // Main hashrate reading requires >= 7:1 in both modes.
            #expect(try Self.contrast(FleetTheme.hashrateInk, FleetTheme.hashrateSurface, style: style) >= 7)

            for border in [FleetTheme.controlBorder, FleetTheme.chartFourth] {
                for background in [FleetTheme.canvas, FleetTheme.surface, FleetTheme.raised] {
                    #expect(try Self.contrast(border, background, style: style) >= 3)
                }
            }
        }
    }

    @Test func headerArtworkResolvesLightAndDarkAssetVariants() throws {
        let light = try #require(
            UIImage(
                named: "HashFleetHeader",
                in: .main,
                compatibleWith: UITraitCollection(userInterfaceStyle: .light)
            )
        )
        let dark = try #require(
            UIImage(
                named: "HashFleetHeader",
                in: .main,
                compatibleWith: UITraitCollection(userInterfaceStyle: .dark)
            )
        )
        #expect(light.pngData() != dark.pngData())
    }

    @MainActor
    @Test func desktopLogoEnlargementDoesNotChangeMobileHeaderArtwork() throws {
        let image = try #require(ImageRenderer(content: FleetHeaderArtwork()).uiImage)
        #expect(image.size == CGSize(width: 34, height: 34))
    }

    @Test func appearancePersistsBothModesAndRecoversFromInvalidValues() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = FleetPreferences(defaults: defaults)
        #expect(preferences.appearance == .system)
        for appearance in FleetPreferences.Appearance.allCases {
            preferences.appearance = appearance
            #expect(defaults.string(forKey: FleetPreferences.Keys.appearance) == appearance.rawValue)
            #expect(FleetPreferences(defaults: defaults).appearance == appearance)
        }
        defaults.set("invalid", forKey: FleetPreferences.Keys.appearance)
        #expect(FleetPreferences(defaults: defaults).appearance == .system)
        #expect(preferences.realtimeMonitoring == FleetPreferences.defaultRealtimeMonitoring)
    }

    @Test func systemAppearanceMigratesOnceAndPreservesLaterOverrides() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("dark", forKey: FleetPreferences.Keys.appearance)
        defaults.set("miner-data-sentinel", forKey: "preserve.other.setting")
        let preferences = FleetPreferences(defaults: defaults)
        #expect(preferences.appearance == .system)
        #expect(preferences.appearance.colorScheme == nil)
        #expect(FleetPreferences.Appearance.light.colorScheme == .light)
        #expect(FleetPreferences.Appearance.dark.colorScheme == .dark)
        preferences.appearance = .light
        #expect(FleetPreferences(defaults: defaults).appearance == .light)
        #expect(defaults.string(forKey: "preserve.other.setting") == "miner-data-sentinel")
        preferences.appearance = .system
        #expect(FleetPreferences(defaults: defaults).appearance == .system)
    }

    @Test func persistenceSavesAndRestoresAllSettings() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        let prefs = FleetPreferences(defaults: defaults)
        #expect(prefs.sort == FleetPreferences.defaultSort)
        #expect(prefs.ascending == FleetPreferences.defaultAscending)
        #expect(prefs.compactCards == FleetPreferences.defaultCompactCards)
        #expect(prefs.realtimeMonitoring == FleetPreferences.defaultRealtimeMonitoring)
        #expect(prefs.blockNotificationsEnabled == FleetPreferences.defaultBlockNotificationsEnabled)

        prefs.sort = .hashrate
        prefs.ascending = false
        prefs.compactCards = true
        prefs.realtimeMonitoring = false
        prefs.blockNotificationsEnabled = true

        #expect(defaults.string(forKey: FleetPreferences.Keys.sort) == "hashrate")
        #expect(defaults.bool(forKey: FleetPreferences.Keys.ascending) == false)
        #expect(defaults.bool(forKey: FleetPreferences.Keys.compactCards) == true)
        #expect(defaults.bool(forKey: FleetPreferences.Keys.realtimeMonitoring) == false)
        #expect(defaults.bool(forKey: FleetPreferences.Keys.blockNotificationsEnabled) == true)

        let restored = FleetPreferences(defaults: defaults)
        #expect(restored.sort == .hashrate)
        #expect(restored.ascending == false)
        #expect(restored.compactCards == true)
        #expect(restored.realtimeMonitoring == false)
        #expect(restored.blockNotificationsEnabled == true)
    }

    // MARK: - Corrupt Defaults

    @Test func corruptDefaultsFallBackToValidDefaultsPreservingStore() throws {
        let (defaults, suite) = try makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("nonexistent_sort_option", forKey: FleetPreferences.Keys.sort)
        defaults.set("corrupt_bool", forKey: FleetPreferences.Keys.ascending)
        defaults.set(["unexpected": "dictionary"], forKey: FleetPreferences.Keys.compactCards)
        defaults.set(["unexpected": "dictionary"], forKey: FleetPreferences.Keys.realtimeMonitoring)

        let prefs = FleetPreferences(defaults: defaults)
        #expect(prefs.sort == .name)
        #expect(prefs.ascending == true)
        #expect(prefs.compactCards == false)
        #expect(prefs.realtimeMonitoring == FleetPreferences.defaultRealtimeMonitoring)
    }

}
