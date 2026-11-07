import AppKit
import SwiftUI
import Testing
@testable import HashFleetMac

@Suite("Settings control and separator clearance") @MainActor
struct FleetSettingsSpacingTests {
    private func size<V: View>(_ view: V) throws -> CGSize {
        let renderer = ImageRenderer(content: view.frame(width: 240))
        renderer.scale = 2
        return try #require(renderer.nsImage).size
    }

    @Test(arguments: [true, false])
    func separatorAddsClearanceWithoutShrinkingTheControl(isForm: Bool) throws {
        let control = Color.red.frame(height: 44)
        let plain = try size(FleetSettingsRow(showsSeparator: false) { control }
            .environment(\.fleetSettingsIsForm, isForm))
        let separated = try size(FleetSettingsRow { control }
            .environment(\.fleetSettingsIsForm, isForm))
        #expect(plain.height >= 44)
        #expect(abs(separated.height - plain.height - 8.5) < 0.1)
        #expect(separated.width == plain.width)
    }

    @Test func manualAndNavigationSeparatorsAreOutsideTheOriginalControl() throws {
        let control = Color.red.frame(height: 44)
        let manual = try size(control.fleetSettingsRowSeparator())
        let navigation = try size(control.fleetSettingsNavigationRow())
        #expect(abs(manual.height - 52.5) < 0.1)
        #expect(abs(navigation.height - 72.5) < 0.1)
    }

    @Test func lastRowDoesNotAcquireAnEmptySeparatorGap() throws {
        let rendered = try size(FleetSettingsRow(showsSeparator: false) {
            Color.red.frame(height: 44)
        }.environment(\.fleetSettingsIsForm, true))
        #expect(rendered.height == 44)
    }

    @Test func longAccessibleLabelsGrowInsteadOfClippingAtTheDivider() throws {
        let rendered = try size(FleetSettingsRow {
            Text("Background checks are best effort. The saved widget reading stays visible when the local miner network cannot be reached.")
                .font(.largeTitle)
                .fixedSize(horizontal: false, vertical: true)
        }.environment(\.fleetSettingsIsForm, true)
            .environment(\.dynamicTypeSize, .accessibility3))
        #expect(rendered.height > 100)
    }
}
