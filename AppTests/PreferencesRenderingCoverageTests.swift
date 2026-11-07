import Foundation
import SwiftUI
import Testing
import HashFleetCore
@testable import HashFleet

@Suite(.serialized) @MainActor
struct PreferencesRenderingCoverageTests {

    // MARK: - App/Features/Settings

    @Test func renderMonitoringSettingsView() async throws {
        let fixture = try FleetRenderFixture(demo: true)
        defer { fixture.cleanup() }
        let storage = FleetGlanceStorage(defaults: fixture.store.defaults)
        let coordinator = FleetGlanceCoordinator(defaults: fixture.store.defaults, storage: storage, isTesting: true, activityName: "test")
        let view = MonitoringSettingsView(store: fixture.store, coordinator: coordinator)

        let rendered = try await FleetViewRenderHarness.render(view)
        #expect(rendered.pixelVariation > 0)
        #expect(rendered.visibleText.contains("Settings") || rendered.visibleText.contains("Your fleet"))
    }

    @Test func renderFleetLiveActivitySettingsPage() async throws {
        let fixture = try FleetRenderFixture(demo: true)
        defer { fixture.cleanup() }
        let storage = FleetGlanceStorage(defaults: fixture.store.defaults)
        let coordinator = FleetGlanceCoordinator(defaults: fixture.store.defaults, storage: storage, isTesting: true, activityName: "test")
        let view = FleetLiveActivitySettingsPage(store: fixture.store, coordinator: coordinator)

        let rendered = try await FleetViewRenderHarness.render(view)
        #expect(rendered.pixelVariation > 0)
        #expect(rendered.visibleText.contains("Live Activity") || rendered.visibleText.contains("Status"))
    }

    @Test func renderFleetSystemFeaturesView() async throws {
        let view1 = FleetSystemFeaturesView(sharesSavedReadings: true)
        let view2 = FleetSystemFeaturesView(sharesSavedReadings: false)

        let r1 = try await FleetViewRenderHarness.render(NavigationStack { view1 }, height: 2_400)
        let r2 = try await FleetViewRenderHarness.render(NavigationStack { view2 }, height: 2_400)
        #expect(r1.pixelVariation > 1)
        #expect(r2.pixelVariation > 1)
        #expect(r1.pngData != r2.pngData)
        #expect(r1.visibleText.contains("Sharing enabled"))
        #expect(r2.visibleText.contains("Off"))
    }

    @Test func renderFleetGlancePreviewCard() async throws {
        let glance1 = FleetGlance(
            updatedAt: Date(),
            onlineCount: 3,
            minerCount: 3,
            hashrateGHs: 3_020,
            powerWatts: 51,
            isDemo: true
        )
        let glance2 = FleetGlance(
            updatedAt: Date(timeIntervalSinceNow: -100),
            onlineCount: 0,
            minerCount: 0,
            hashrateGHs: 0,
            powerWatts: 0,
            isDemo: false
        )
        let view1 = FleetGlancePreviewCard(glance: glance1, showsDetails: true)
        let view2 = FleetGlancePreviewCard(glance: glance2, showsDetails: false)

        let r1 = try await FleetViewRenderHarness.render(view1)
        let r2 = try await FleetViewRenderHarness.render(view2)
        #expect(r1.pixelVariation > 0)
        #expect(r2.pixelVariation > 0)
        #expect(r1.pngData != r2.pngData)
        #expect(r1.visibleText.contains("sample miners"))
        #expect(r2.visibleText.contains("GET STARTED"))
        #expect(r2.visibleText.contains("0 miners"))
    }

    @Test func renderFleetPreferencesView() async throws {
        let fixture = try FleetRenderFixture(demo: true)
        defer { fixture.cleanup() }
        let view = FleetPreferencesView(preferences: fixture.store.preferences, store: fixture.store)

        let rendered = try await FleetViewRenderHarness.render(view)
        #expect(rendered.pixelVariation > 0)
        #expect(rendered.visibleText.contains("Appearance"))
    }

    @Test func renderFleetNotificationSettingsView() async throws {
        let fixture = try FleetRenderFixture(demo: true)
        defer { fixture.cleanup() }
        let view = FleetNotificationSettingsView(preferences: fixture.store.preferences)

        let rendered = try await FleetViewRenderHarness.render(NavigationStack { view }, height: 1_600)
        #expect(rendered.pixelVariation > 0)
        #expect(rendered.visibleText.contains("Notifications"))
    }

    @Test func notificationChoicesAndSessionPreviewRenderInlineInAppSettings() async throws {
        let fixture = try FleetRenderFixture(demo: true)
        defer { fixture.cleanup() }
        let coordinator = FleetGlanceCoordinator(defaults: fixture.store.defaults,
            storage: FleetGlanceStorage(defaults: fixture.store.defaults), isTesting: true, activityName: "test")
        let view = MonitoringSettingsView(store: fixture.store, coordinator: coordinator,
                                          notificationsExpanded: true)
            .environment(\.fleetGuidedDemo, true)
        let rendered = try await FleetViewRenderHarness.render(
            NavigationStack { view }, height: 3_600,
            readiness: { $0.visibleText.contains("Preview session-best popup") })
        #expect(rendered.pixelVariation > 0)
        #expect(rendered.visibleText.contains("App settings"))
        #expect(rendered.visibleText.contains("Notifications and banners"))
        #expect(rendered.visibleText.contains("Session-best alerts"))
        #expect(!rendered.visibleText.contains("Activity list"))
    }

    @Test func sessionRecordRendersTheExistingIllustratedCelebration() async throws {
        let celebration = FleetCelebration(kind: .bestShareSession, deviceID: UUID(),
            minerName: "Workshop Gamma", value: "9.20M", detail: "New best share this session")
        let rendered = try await FleetViewRenderHarness.render(
            FleetCelebrationView(celebration: celebration, onViewMiner: {}, onDismiss: {},
                                 onDisableSessionBestAlerts: {})
                // This mounted-pixel check needs settled digits, not an intermediate numeric transition.
                // The native UI scenario separately exercises the real animated popup for 12 seconds.
                .transaction { $0.disablesAnimations = true },
            readiness: { $0.visibleText.contains("SESSION BEST") && $0.visibleText.contains("9.20M") })
        #expect(rendered.pixelVariation > 0)
        #expect(rendered.visibleText.contains("Workshop Gamma hit a new best"))
        #expect(rendered.visibleText.contains("9.20M"))
        #expect(rendered.visibleText.contains("Keep mining"))
        #expect(rendered.visibleText.contains("Turn off session-best alerts"))
    }

    @Test func renderFleetPowerAlertsView() async throws {
        let fixture = try FleetRenderFixture(demo: true)
        defer { fixture.cleanup() }

        let emptyView = FleetPowerAlertsView(devices: [], preferences: fixture.store.powerAlerts, isDemo: false)
        let r1 = try await FleetViewRenderHarness.render(emptyView)
        #expect(r1.pixelVariation > 0)
        #expect(r1.visibleText.contains("No miners yet"))
        #expect(r1.visibleText.contains("Add a miner to configure its power alert."))

        let populatedView = FleetPowerAlertsView(devices: fixture.store.devices, preferences: fixture.store.powerAlerts, isDemo: false)
        let r2 = try await FleetViewRenderHarness.render(populatedView)
        #expect(r2.pixelVariation > 0)
        #expect(r1.pngData != r2.pngData)
    }

    @Test func renderFleetTemperatureAlertsView() async throws {
        let fixture = try FleetRenderFixture(demo: true)
        defer { fixture.cleanup() }

        let emptyView = FleetTemperatureAlertsView(devices: [], preferences: fixture.store.temperatureAlerts, isDemo: false)
        let r1 = try await FleetViewRenderHarness.render(emptyView)
        #expect(r1.pixelVariation > 0)
        #expect(r1.visibleText.contains("No miners yet"))
        #expect(r1.visibleText.contains("Add a miner to configure its temperature alert."))

        let populatedView = FleetTemperatureAlertsView(devices: fixture.store.devices, preferences: fixture.store.temperatureAlerts, isDemo: false)
        let r2 = try await FleetViewRenderHarness.render(populatedView)
        #expect(r2.pixelVariation > 0)
        #expect(r1.pngData != r2.pngData)
    }

    @Test func renderMonitoringNoteRow() async throws {
        let view = MonitoringNoteRow(symbol: "clock", title: "Note Title", message: "Note body", tint: .blue)
        let rendered = try await FleetViewRenderHarness.render(view)
        #expect(rendered.pixelVariation > 0)
        #expect(rendered.visibleText.contains("Note Title"))
        #expect(rendered.visibleText.contains("Note body"))
    }

    // MARK: - App/Features/Tour

    @Test func renderFleetTourView() async throws {
        // Note: The tour view test only validates the initial loading/sandbox setup page, not all lessons.
        let view = FleetTourView(dontShowAgain: .constant(false))
        let rendered = try await FleetViewRenderHarness.render(view)
        #expect(rendered.pixelVariation > 0)
        #expect(rendered.visibleText.contains("Sample miners"))
        #expect(rendered.visibleText.contains("Next"))
        #expect(rendered.visibleText.contains("show again"))
        // OCR does not normalize the typographic apostrophe. Exact native labels
        // and toggle actions remain a separate acceptance boundary.
    }

    @Test func renderFleetGuidedSpotlight() async throws {
        let view1 = FleetGuidedSpotlight(target: CGRect(x: 40, y: 120, width: 220, height: 48), actionTitle: "Tap target", isInteractive: true, action: {})
        let view2 = FleetGuidedSpotlight(target: CGRect(x: 40, y: 120, width: 220, height: 48), actionTitle: "Highlight target", isInteractive: false, action: {})
        let view3 = FleetGuidedSpotlight(target: nil, actionTitle: "Wait", isInteractive: true, action: {})

        let r1 = try await FleetViewRenderHarness.render(view1)
        let r2 = try await FleetViewRenderHarness.render(view2)
        let r3 = try await FleetViewRenderHarness.render(view3)

        #expect(r1.pixelVariation > 0)
        #expect(r2.pixelVariation > 0)
        #expect(r3.pixelVariation > 0)
        #expect(r1.pngData != r2.pngData, "tap cue and read-only highlight should render differently")
        #expect(r1.pngData != r3.pngData, "targeted and preparing states should render differently")
        #expect(r2.pngData != r3.pngData, "highlight and preparing states should render differently")

        #expect(r3.visibleText.contains("Preparing"))
    }

    // MARK: - App/Features/Celebration

    @Test func renderFleetCelebrationView() async throws {
        let c1 = FleetCelebration(kind: .bestShareAllTime, deviceID: UUID(), minerName: "Gamma", value: "392.00M", detail: "Best ever")
        let view1 = FleetCelebrationView(celebration: c1, onViewMiner: {}, onDismiss: {},
                                        onDisableSessionBestAlerts: {})

        let c2 = FleetCelebration(kind: .blockFound, deviceID: UUID(), minerName: "Gamma", value: "912,345", detail: "Block found")
        let view2 = FleetCelebrationView(celebration: c2, onViewMiner: {}, onDismiss: {},
                                        onDisableSessionBestAlerts: {})

        let r1 = try await FleetViewRenderHarness.render(
            view1, readiness: { $0.visibleText.contains("NEW HIGH SCORE") })
        let r2 = try await FleetViewRenderHarness.render(
            view2, readiness: { $0.visibleText.contains("BLOCK FOUND") })

        #expect(r1.pixelVariation > 0)
        #expect(r2.pixelVariation > 0)
        #expect(r1.pngData != r2.pngData)
        #expect(r1.visibleText.contains("NEW HIGH SCORE"))
        #expect(r2.visibleText.contains("BLOCK FOUND"))
        #expect(!r1.visibleText.contains("Turn off session-best alerts"))
        #expect(!r2.visibleText.contains("Turn off session-best alerts"))
    }

    // MARK: - App/Design

    @Test func renderFleetStartupSplash() async throws {
        let view = FleetStartupSplash(holdForTesting: true, onContinue: {})
        let rendered = try await FleetViewRenderHarness.render(view)
        // holdForTesting keeps the title hidden. This is a raster-only artwork check,
        // not a claim about visible readiness copy, accessibility text, or continuation.
        #expect(rendered.pixelVariation > 0)
    }

    @Test func renderFleetPerformanceSettingsView() async throws {
        let view = FleetPerformanceSettingsView()
        let rendered = try await FleetViewRenderHarness.render(view)
        #expect(rendered.pixelVariation > 0)
        #expect(rendered.visibleText.contains("Frame Pacing Diagnostics"))
    }

    @Test func renderFleetPerformanceOverlay() async throws {
        // The overlay is hidden by default. Render it inside a container to verify hidden semantics
        // and avoid asserting content that won't be drawn or accessible.
        let view = VStack {
            Text("Background content").accessibilityLabel("Background content")
            FleetPerformanceOverlay()
        }
        let rendered = try await FleetViewRenderHarness.render(view)
        #expect(rendered.pixelVariation > 0)
        #expect(rendered.visibleText == "Background content")
    }

    @Test func renderFleetAnimatedArtAndIllustrations() async throws {
        let view1 = FleetAnimatedArt(.fleetCluster, size: CGSize(width: 100, height: 100))
        let view2 = FleetAnimatedArt(.minerCooling, size: CGSize(width: 100, height: 100))

        let r1 = try await FleetViewRenderHarness.render(view1)
        let r2 = try await FleetViewRenderHarness.render(view2)
        #expect(r1.pixelVariation > 0)
        #expect(r2.pixelVariation > 0)
        #expect(r1.pngData != r2.pngData)

        let view3 = FleetEnergyIllustration()
        let r3 = try await FleetViewRenderHarness.render(view3)
        #expect(r3.pixelVariation > 0)

        let view4 = FleetNetworkIllustration()
        let r4 = try await FleetViewRenderHarness.render(view4)
        #expect(r4.pixelVariation > 0)

        let view5 = FleetReportIllustration()
        let r5 = try await FleetViewRenderHarness.render(view5)
        #expect(r5.pixelVariation > 0)
    }

    @Test func renderBitsy() async throws {
        let view1 = BitsyView(mood: .party, size: 100)
        let r1 = try await FleetViewRenderHarness.render(view1)
        #expect(r1.pixelVariation > 0)

        let view2 = BitsySays(mood: .celebrate, message: "Hello Bitsy")
        let r2 = try await FleetViewRenderHarness.render(
            view2, readiness: { $0.visibleText.contains("Hello Bitsy") })
        #expect(r2.pixelVariation > 0)
        #expect(r2.visibleText.contains("Hello Bitsy"))
    }

    @Test func renderAppDesignSupportingComponents() async throws {
        let view1 = FleetLoadingSkeleton()
        let r1 = try await FleetViewRenderHarness.render(view1)
        #expect(r1.pixelVariation > 0)

        let view2 = FleetMinerFansImage()
        let r2 = try await FleetViewRenderHarness.render(view2)
        #expect(r2.pixelVariation > 0)

        let view3 = FleetSensitiveValue(title: "Secret", value: "abcdef", identifier: "test.secret")
        let r3 = try await FleetViewRenderHarness.render(view3)
        #expect(r3.pixelVariation > 0)
        #expect(r3.visibleText.contains("Secret"))
    }
}
