import SwiftUI
import Testing
@testable import HashFleet

@Suite("Shared palette parity")
struct FleetThemePaletteTests {
    @MainActor
    @Test func sharedPaletteKeepsTheApprovedLightAndDarkColors() {
        let palette: [(Color, UInt32, UInt32)] = [
            (FleetTheme.canvas, 0xFFFFFF, 0x02090C),
            (FleetTheme.surface, 0xF5F5F5, 0x10191D),
            (FleetTheme.raised, 0xE5E5E5, 0x182126),
            (FleetTheme.ink, 0x21201E, 0xF4F6F7),
            (FleetTheme.secondary, 0x595959, 0xBFC6CC),
            (FleetTheme.accent, 0x8A5000, 0xF5AC26),
            (FleetTheme.positive, 0x356447, 0x25A354),
            (FleetTheme.warning, 0x864705, 0xF5AC26),
            (FleetTheme.separator, 0xCCCCCC, 0x27343A)
        ]
        for scheme in [ColorScheme.light, .dark] {
            var environment = EnvironmentValues()
            environment.colorScheme = scheme
            for (color, light, dark) in palette {
                let rgb = scheme == .light ? light : dark
                let actual = color.resolve(in: environment)
                #expect(abs(actual.red - Float((rgb >> 16) & 255) / 255) < 0.005)
                #expect(abs(actual.green - Float((rgb >> 8) & 255) / 255) < 0.005)
                #expect(abs(actual.blue - Float(rgb & 255) / 255) < 0.005)
                #expect(actual.opacity == 1)
            }
        }
    }
}
