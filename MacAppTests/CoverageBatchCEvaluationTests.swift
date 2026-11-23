import SwiftUI
import AppKit
import Observation
import Testing
import HashFleetCore
@testable import HashFleetMac

@Observable
@MainActor
private final class EffectDriver {
    var shares: Int? = 10
    var best: Decimal? = 5
    var label = "Row"
}

private struct EffectHarness: View {
    let driver: EffectDriver
    var body: some View {
        VStack {
            Text("\(driver.shares ?? 0)").fleetShareRise(driver.shares)
            Text("\(driver.best.map { "\($0)" } ?? "-")").fleetRecordShine(driver.best)
            FleetSensitiveValue(title: driver.label, value: "192.168.1.5", identifier: "test.sensitive")
            FleetSensitiveValue(title: "Empty", value: "", identifier: "test.empty")
        }
        .frame(width: 300, height: 300)
    }
}

@Suite("Coverage Batch C", .serialized)
@MainActor
struct CoverageBatchCEvaluationTests {
    private func host<V: View>(_ view: V) -> (NSHostingView<V>, NSWindow) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        return (host, window)
    }

    private func pump(_ host: NSView, _ seconds: Double = 0.05) async {
        try? await Task.sleep(for: .seconds(seconds))
        host.layoutSubtreeIfNeeded()
    }

    @Test func changeEffectsRespondToIncreasesDropsAndMissingValues() async {
        let driver = EffectDriver()
        let (host, window) = host(EffectHarness(driver: driver))
        defer { window.close() }
        await pump(host)
        driver.shares = 12
        driver.best = 9
        await pump(host)
        driver.shares = 5000
        driver.best = 10
        await pump(host, 0.1)
        driver.shares = 3
        driver.best = 1
        await pump(host)
        driver.shares = nil
        driver.best = nil
        await pump(host)
        driver.shares = 4
        driver.best = 2
        driver.label = "Renamed"
        await pump(host, 0.3)
    }

    @Test func rowViewsRenderUnderReduceMotionAndInactiveScene() async {
        let driver = EffectDriver()
        let view = EffectHarness(driver: driver)
            .environment(\.scenePhase, .inactive)
        let (host, window) = host(view)
        defer { window.close() }
        await pump(host)
        driver.shares = 99
        driver.best = 42
        await pump(host)
    }

    @Test func shareRiseTextAndDisclosurePolicy() {
        #expect(FleetShareRiseText.text(previous: 5, current: 5) == nil)
        #expect(FleetShareRiseText.text(previous: 5, current: 4) == nil)
        #expect(FleetShareRiseText.text(previous: 5, current: 6) == "+1")
        #expect(FleetShareRiseText.text(previous: 0, current: 1000) == "+999+")

        var disclosure = FleetSensitiveValueDisclosure()
        #expect(disclosure.visibleValue(for: "a", isActive: true) == nil)
        disclosure.reveal("a", isActive: false)
        #expect(disclosure.visibleValue(for: "a", isActive: true) == nil)
        disclosure.reveal("a", isActive: true)
        #expect(disclosure.visibleValue(for: "a", isActive: true) == "a")
        #expect(disclosure.visibleValue(for: "a", isActive: false) == nil)
        #expect(disclosure.visibleValue(for: "b", isActive: true) == nil)
        var written: [String] = []
        #expect(disclosure.copy("a", isActive: true) { written.append($0) })
        #expect(!disclosure.copy("b", isActive: true) { written.append($0) })
        #expect(written == ["a"])
        disclosure.hide()
        #expect(!disclosure.copy("a", isActive: true) { written.append($0) })
        disclosure.reveal("", isActive: true)
        #expect(!disclosure.copy("", isActive: true) { written.append($0) })
    }
}
