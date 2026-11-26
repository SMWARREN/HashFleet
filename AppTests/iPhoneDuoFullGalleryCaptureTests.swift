import Foundation
import Testing
import SwiftUI
import HashFleetCore
@testable import HashFleet

/// Renders every Hash Fleet page on both iPhone Duo screens offscreen (no Simulator window),
/// using the demo fleet. Output: docs/screenshots/duo/all/.
@Suite(.serialized)
@MainActor
struct IPhoneDuoFullGalleryCaptureTests {
    private static let outputDir = URL(
        fileURLWithPath: "/Users/saint/dev/hashfleet-iphone-duo/docs/screenshots/duo/all"
    )
    private static let outer = CGSize(width: 466, height: 678)
    private static let inner = CGSize(width: 669, height: 951)

    private static let pages: [(String, FleetSidebarDestination)] = [
        ("overview", .overview),
        ("network", .network),
        ("energy", .energy),
        ("achievements", .achievements),
        ("reports", .reports),
        ("backup", .backup),
        ("preferences", .preferences),
        ("about", .about),
        ("support", .support)
    ]

    @Test
    func captureEveryPageOnBothDuoScreens() async throws {
        let fixture = try FleetRenderFixture(demo: true)
        defer { fixture.cleanup() }
        await fixture.insights.refresh()
        try FileManager.default.createDirectory(at: Self.outputDir, withIntermediateDirectories: true)
        let store = fixture.store
        let insights = fixture.insights
        let device = try #require(store.visibleDevices.first)

        var destinations = Self.pages
        destinations.insert(("miner", .miner(device.id)), at: 1)

        for (index, entry) in destinations.enumerated() {
            let (name, destination) = entry
            let prefix = String(format: "%02d", index + 1)

            // Unfolded inner screen: full app, menu docked on the left panel.
            let split = FleetSplitView(
                store: store,
                insights: insights,
                coordinator: nil,
                startupReady: true,
                fleetPath: .constant(NavigationPath()),
                sidebarSelection: .constant(destination)
            )
            .environment(\.horizontalSizeClass, .regular)
            try await save(split, size: Self.inner, as: "\(prefix)-inner-\(name).png")

            // Folded outer screen: the same page as a phone would show it.
            let page = NavigationStack { Self.page(destination, store: store, insights: insights) }
                .environment(\.horizontalSizeClass, .compact)
            try await save(page, size: Self.outer, as: "\(prefix)-outer-\(name).png")
        }

        let add = NavigationStack { AddMinerView(store: store) }
        try await save(add.environment(\.horizontalSizeClass, .regular), size: Self.inner, as: "11-inner-add-miner.png")
        try await save(add.environment(\.horizontalSizeClass, .compact), size: Self.outer, as: "11-outer-add-miner.png")
    }

    private func save<V: View>(_ view: V, size: CGSize, as fileName: String) async throws {
        let rendered = try await FleetViewRenderHarness.render(view, width: size.width, height: size.height)
        #expect(!rendered.visibleText.isEmpty, "\(fileName) rendered no visible text")
        try rendered.pngData.write(to: Self.outputDir.appendingPathComponent(fileName))
        Attachment.record(rendered.pngData, named: fileName)
    }

    @ViewBuilder
    private static func page(
        _ destination: FleetSidebarDestination,
        store: FleetStore,
        insights: MiningInsightsStore
    ) -> some View {
        switch destination {
        case .overview: DashboardView(store: store, insights: insights)
        case .miner(let id): MinerDetailDestinationView(deviceID: id, store: store, insights: insights)
        case .network: NetworkInsightsView(fleet: store, insights: insights)
        case .energy: FleetEnergyView(store: store)
        case .achievements:
            MiningAchievementsView(devices: FleetReleaseFeatures.visibleDevices(store.savedDevices))
        case .reports: FleetReportView(store: store)
        case .backup: FleetBackupView(store: store)
        case .preferences: FleetPreferencesView(preferences: store.preferences, store: store, onPreviewCelebration: nil)
        case .about: AboutView(store: store)
        case .support: DeveloperSupportView()
        case .monitoring: EmptyView()
        }
    }
}
