import Foundation
import SwiftUI
import Testing
import UIKit
@testable import HashFleet

@Suite("Hash Fleet system-launch branding") @MainActor
struct FleetSystemFeatureBrandingTests {
    @Test func openingIntentKeepsItsIdentityAndBrandedVisibleTitle() {
        #expect(String(localized: OpenFleetIntent.title) == "Open Hash Fleet")
        #expect(OpenFleetIntent.openAppWhenRun)
        #expect(FleetSystemIntegration.fleetURL.absoluteString == "hashfleet://fleet")
        #expect(Bundle.main.bundleIdentifier == "app.hashfleet")
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String == "Hash Fleet")
    }

    @Test func embeddedExtensionsUseBrandedNamesWithoutChangingTheirIdentifiers() throws {
        let plugins = try #require(Bundle.main.builtInPlugInsURL)
        let urls = try FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil)
        let expectedIDs: Set<String> = [
            "app.hashfleet.widgets", "app.hashfleet.notification-service"
        ]
        var identifiers: Set<String> = []
        for url in urls where url.pathExtension == "appex" {
            let bundle = try #require(Bundle(url: url))
            let identifier = try #require(bundle.bundleIdentifier)
            identifiers.insert(identifier)
            #expect(bundle.object(forInfoDictionaryKey: "CFBundleName") as? String == "Hash Fleet")
        }
        #expect(identifiers == expectedIDs)
    }

    @Test func systemFeatureSettingsRenderTheActualBrandedLauncher() async throws {
        let rendered = try await FleetViewRenderHarness.render(
            NavigationStack {
                FleetSystemFeaturesView(sharesSavedReadings: false)
            }, width: 390, height: 2_200)
        #expect(rendered.visibleText.contains("Open Hash Fleet"))
        #expect(!rendered.visibleText.localizedCaseInsensitiveContains("Axe Fleet"))
        #expect(!rendered.visibleText.localizedCaseInsensitiveContains("AxeFleet"))
        #expect(rendered.pixelVariation > 1)
        let artwork = try #require(UIImage(named: "HashFleetBrand"))
        #expect(artwork.size.width > 0 && artwork.size.height > 0)
    }
}
