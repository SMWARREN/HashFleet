import AppIntents
import Foundation
import SwiftUI
import Testing
import WidgetKit
import HashFleetCore
@testable import HashFleet
@testable import HashFleetWidgetTestSupport

extension FleetWidgetRefreshIntegrationTests {
    @Test(arguments: ["small", "medium", "large"])
    func loadingIsVisibleForSystemInvalidationAndAProviderLease(familyName: String) async throws {
        let family: WidgetFamily
        let size: CGSize
        switch familyName {
        case "small": family = .systemSmall; size = CGSize(width: 184, height: 184)
        case "medium": family = .systemMedium; size = CGSize(width: 360, height: 184)
        default: family = .systemLarge; size = CGSize(width: 360, height: 376)
        }
        let now = Date()
        let saved = HashFleetWidgetTestSupport.FleetGlance(updatedAt: now, onlineCount: 1,
            minerCount: 1, hashrateGHs: 1_200, powerWatts: 19, isDemo: false)
        for systemInvalidated in [false, true] {
            let entry = HashFleetWidgetTestSupport.FleetWidgetEntry(date: now, glance: saved,
                refresh: .init(isEnabled: true, message: systemInvalidated ? nil : "Refreshing…",
                    isRefreshing: !systemInvalidated))
            let content = HashFleetWidgetTestSupport.FleetWidgetContent(entry: entry, family: family)
                .invalidatableContent()
                .redacted(reason: systemInvalidated ? .invalidated : [])
                .background(HashFleetWidgetTestSupport.FleetWidgetTheme.canvas)
                .preferredColorScheme(systemInvalidated ? .light : .dark)
                .frame(width: size.width, height: size.height)
                .ignoresSafeArea()
            let busy = try await FleetViewRenderHarness.render(content, width: size.width, height: size.height)
            #expect(busy.visibleText.contains("Refreshing"), "Observed pixels: \(busy.visibleText)")
            let idleEntry = HashFleetWidgetTestSupport.FleetWidgetEntry(date: now, glance: saved,
                refresh: .init(isEnabled: true, message: nil))
            let idle = try await FleetViewRenderHarness.render(
                HashFleetWidgetTestSupport.FleetWidgetContent(entry: idleEntry, family: family)
                    .background(HashFleetWidgetTestSupport.FleetWidgetTheme.canvas)
                    .frame(width: size.width, height: size.height).ignoresSafeArea(),
                width: size.width, height: size.height)
            #expect(!idle.visibleText.contains("Refreshing"))
            #expect(idle.pngData != busy.pngData)
            let hidden = try await FleetViewRenderHarness.render(content.redacted(reason: [.privacy, .invalidated]),
                width: size.width, height: size.height)
            #expect(!hidden.visibleText.contains("1.20"))
            #expect(entry.glance.updatedAt == saved.updatedAt)
        }
    }

    @Test func invalidationCannotEnableAnUnpreparedActionOrInventAReadTime() {
        let unprepared = HashFleetWidgetTestSupport.FleetWidgetRefreshPresentation(
            isEnabled: false, message: "Open app to prepare refresh")
        #expect(unprepared.invalidated(true) == unprepared)
        let ready = HashFleetWidgetTestSupport.FleetWidgetRefreshPresentation(isEnabled: true, message: nil)
        #expect(ready.invalidated(false) == ready)
        let busy = ready.invalidated(true)
        #expect(busy.isRefreshing && busy.message == "Refreshing…")
        #expect(busy.invalidated(false) == busy, "A real provider lease remains busy without system invalidation")
    }
}
