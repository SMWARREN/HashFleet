import AppKit
import SwiftUI
import HashFleetCore
@testable import HashFleetMac

// Link against the Debug app module after build-for-testing. Its @main is never run.
// This renders production cards with an isolated Demo store and a network-blocking
// session. No app is activated and no window is created. Native WindowServer click
// acceptance is separate from these actual-surface pixel and geometry checks.
@main
struct NativeMinerLayoutChecks {
    struct Failure: Error, CustomStringConvertible { let description: String }
    @MainActor final class Probe { var frames: [String: CGRect] = [:] }

    @MainActor static func main() {
        do { try run() } catch {
            FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
            exit(1)
        }
    }

    @MainActor static func run() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        try require(app.activationPolicy() == .prohibited, "Activation must be prohibited")
        try require(!app.isActive && app.windows.isEmpty, "Runner must have no active app or window")
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "./native-miner-layout", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let suite = "app.hashfleet.offscreen.miner.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BlockedProtocol.self]
        config.urlCache = nil
        let session = URLSession(configuration: config)
        let store = FleetStore(defaults: defaults, session: session)
        defer {
            store.cancelRefresh()
            store.cancelLiveMonitoring()
            store.capabilities.cancelAll()
            session.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suite)
        }
        store.loadDemo()
        store.preferences.externalDataEnabled = false
        store.preferences.realtimeMonitoring = false
        guard let device = store.visibleDevices.first, let info = store.snapshots[device.id]?.info else {
            throw Failure(description: "Demo fixture must provide a miner and readings")
        }
        let detail = MinerDetailView(device: device, store: store)
        let diagnostics = MinerDiagnosticsModel(info: info)
        let dashboard = DashboardView(store: store)
        var cards = store.visibleDevices
        cards[1].name = "Office Gamma with a deliberately long descriptive name that wraps to make this card taller than its neighbors"
        var spare = device
        spare.id = UUID()
        spare.name = "Spare miner"
        spare.address = "spare-demo.invalid"
        cards.append(spare)
        var checks = 0
        for scheme in [ColorScheme.dark, .light] {
            let expected: UInt32 = scheme == .dark ? 0x10191D : 0xF5F5F5
            for width: CGFloat in [320, 480, 728, 1028, 2056] {
                let image = try render(VStack(spacing: 14) {
                    detail.metrics(info, diagnostics: diagnostics)
                    detail.quickActions
                }, width: width, scheme: scheme)
                try save(image, output.appendingPathComponent("metrics-actions-\(Int(width))-\(scheme).png"))
                // Empty adaptive slots used to leave the trailing half of these rows unpainted.
                try expectPixel(image, x: width - 5, y: 24, rgb: expected)
                checks += 1
            }
            for width: CGFloat in [728, 1028, 2056] {
                let summaryProbe = Probe()
                let summary = try render(dashboard.dashboardPair(wide: true) {
                    observe(FleetBestShareCard(devices: store.visibleDevices, snapshots: store.snapshots,
                        isDemo: true, isCompact: true), id: "best", probe: summaryProbe)
                } trailing: {
                    observe(FleetMilestonesCard(devices: store.visibleDevices, snapshots: store.snapshots,
                        blockObservations: [:], latestBlockEvent: nil, isDemo: true,
                        openAchievements: {}), id: "milestones", probe: summaryProbe)
                }.coordinateSpace(name: "rows"), width: width, scheme: scheme)
                try save(summary, output.appendingPathComponent("dashboard-summary-\(Int(width))-\(scheme).png"))
                guard let best = summaryProbe.frames["best"], let milestones = summaryProbe.frames["milestones"] else {
                    throw Failure(description: "Both actual Overview summary cards must publish their geometry")
                }
                try require(abs(best.height - milestones.height) < 0.5 && abs(best.minY - milestones.minY) < 0.5,
                            "Actual Overview summary surfaces must share their top and bottom: \(summaryProbe.frames)")
                for x in [width / 4, width * 3 / 4] {
                    try expectPixel(summary, x: x, y: summary.size.height - 4, rgb: expected)
                }
                checks += 1

                let totals = try render(dashboard.summaryMetrics(wide: true), width: width, scheme: scheme)
                try save(totals, output.appendingPathComponent("dashboard-totals-\(Int(width))-\(scheme).png"))
                for x in [width / 4, width * 3 / 4] {
                    try expectPixel(totals, x: x, y: totals.size.height - 4, rgb: expected)
                }
                checks += 1

                let hero = try render(detail.hashrateHero(info), width: width, scheme: scheme)
                let history = try render(detail.minerHistoryCard, width: width, scheme: scheme)
                let control = try render(detail.controlMinerCard, width: width, scheme: scheme)
                let primary = try render(detail.desktopPrimarySections(info), width: width, scheme: scheme)
                let heroSurface: UInt32 = scheme == .dark ? 0xF5F5F5 : 0x111111
                try expectPixel(primary, x: width - 5, y: 40, rgb: heroSurface)
                try expectPixel(primary, x: width / 2, y: hero.size.height + 14 + history.size.height / 2, rgb: expected)
                try require(primary.size.height >= hero.size.height + history.size.height + control.size.height + 28,
                            "Hashrate, chart and natural-height controls must stack, never form competing columns")
                try expectPixel(primary, x: width - 5, y: primary.size.height - 32, rgb: expected)
                try save(primary, output.appendingPathComponent("primary-fullwidth-\(Int(width))-\(scheme).png"))
                checks += 1

                let probe = Probe()
                let image = try render(VStack(spacing: 14) {
                    FleetMinerDetailGrid(maximumColumns: 2, minimumColumnWidth: 320, spacing: 14) {
                        observe(detail.bestShares(info), id: "best", probe: probe)
                        observe(detail.identity(info), id: "identity", probe: probe)
                    }
                    FleetMinerDetailGrid(maximumColumns: 2, minimumColumnWidth: 320, spacing: 14) {
                        observe(MinerDiagnosticsView(model: diagnostics), id: "diagnostics", probe: probe)
                        observe(detail.poolsSection, id: "pools", probe: probe)
                    }
                }.coordinateSpace(name: "rows"), width: width, scheme: scheme)
                for pair in [("best", "identity"), ("diagnostics", "pools")] {
                    guard let first = probe.frames[pair.0], let second = probe.frames[pair.1] else {
                        throw Failure(description: "Actual card geometry was not published: \(pair)")
                    }
                    try require(abs(first.height - second.height) < 0.5, "Paired surfaces must match height: \(probe.frames)")
                    try require(abs(first.minY - second.minY) < 0.5, "Paired surfaces must share a row")
                    try require(abs(second.maxX - width) < 0.5, "Actual paired card must fill the trailing edge")
                    let x = second.maxX - 5
                    let y = second.midY
                    try expectPixel(image, x: x, y: y, rgb: expected)
                    checks += 1
                }
                try save(image, output.appendingPathComponent("paired-cards-\(Int(width))-\(scheme).png"))
            }
            for width: CGFloat in [480, 728, 1028, 2056] {
                var naturalHeights: [Int: CGFloat] = [:]
                let frames = FleetMinerDetailGeometry.frames(configuration: .init(itemCount: cards.count, width: width,
                    maximumColumns: 3, minimumColumnWidth: 320, spacing: FleetLayout.cardGridSpacing,
                    balancesFourItems: false)) { index, cellWidth in
                    let probe = Probe()
                    _ = try? render(observe(dashboard.minerCard(cards[index], availableWidth: cellWidth),
                                            id: "card", probe: probe).coordinateSpace(name: "rows"),
                                    width: cellWidth, scheme: scheme)
                    // fittingSize rounds each separate NSHostingView up to whole
                    // points. Read the card's actual fractional layout bounds instead.
                    naturalHeights[index] = probe.frames["card"]?.height
                    return probe.frames["card"]?.height ?? 0
                }
                try require(naturalHeights.count == cards.count, "All real dashboard card measurements must succeed")
                if width == 1028 {
                    try require(abs((naturalHeights[0] ?? 0) - (naturalHeights[1] ?? 0)) > 20,
                                "Fixture must exercise naturally unequal miner cards, not equal-height sample content")
                }
                let container = dashboard.minerCardsContainer(availableWidth: width, columns: 3,
                    gridItems: [], devices: cards)
                let measured = try render(container, width: width, scheme: scheme)
                // Production cards have scroll transitions. Host them inside their
                // real kind of parent so an absent viewport cannot shrink/dim the bitmap.
                let image = try render(ScrollView { container }.scrollIndicators(.hidden)
                    .frame(height: measured.size.height), width: width, scheme: scheme)
                try save(image, output.appendingPathComponent("dashboard-miners-\(Int(width))-\(scheme).png"))
                try require(abs(image.size.height - (frames.map(\.maxY).max() ?? 0)) < 1,
                            "Production dashboard must use the same tallest-card rows: width=\(width), actual=\(image.size.height), expected=\(frames), natural=\(naturalHeights)")
                let raised: UInt32 = scheme == .dark ? 0x182126 : 0xE5E5E5
                for frame in frames {
                    try expectPixel(image, x: frame.maxX - 5, y: frame.minY + 32, rgb: raised)
                    try expectPixel(image, x: frame.maxX - 5, y: frame.maxY - 32, rgb: raised)
                }
                checks += 1
            }
            // These computed detail subviews are extracted before hosting. This
            // proves enlarged-text growth, not the parent environment's column
            // selection. The mounted app UI test checks single-column selection.
            let accessibility = try render(VStack(spacing: 14) {
                detail.primaryMetrics(info, diagnostics: diagnostics)
                detail.quickActions
            }.environment(\.dynamicTypeSize, .accessibility3), width: 480, scheme: scheme)
            try save(accessibility, output.appendingPathComponent("accessibility-480-\(scheme).png"))
            try require(accessibility.size.height > 300, "Enlarged-text rows must grow rather than clip")
            checks += 1
        }
        try require(!app.isActive && app.windows.isEmpty, "Offscreen verification must not activate or create a window")
        print("PASS: \(checks) native production-card surface checks, five widths, dark/light and enlarged-text rendering, no windows or activation")
        print("DEFERRED: physical native mouse clicks and live system popover opening. Simulator coordinate taps are a separate gate.")
    }

    @MainActor static func observe<V: View>(_ view: V, id: String, probe: Probe) -> some View {
        view.onGeometryChange(for: CGRect.self) { $0.frame(in: .named("rows")) } action: { probe.frames[id] = $0 }
    }

    @MainActor static func render<V: View>(_ content: V, width: CGFloat, scheme: ColorScheme) throws -> NSBitmapImageRep {
        let root = content.environment(\.colorScheme, scheme)
            .environment(\.locale, Locale(identifier: "en_US"))
            .frame(width: width).fixedSize(horizontal: false, vertical: true)
            .background(FleetTheme.canvas)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        host.frame = CGRect(x: 0, y: 0, width: width, height: 800)
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        let size = host.fittingSize
        try require(size.width.isFinite && size.height.isFinite && size.height > 0 && size.height < 8192, "Invalid real content size \(size)")
        host.setFrameSize(size)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw Failure(description: "No native bitmap") }
        host.cacheDisplay(in: host.bounds, to: rep)
        // Caching uses the display's backing scale. Keep geometry in points and
        // convert only at the pixel read, including on Retina displays.
        rep.size = size
        return rep
    }

    static func save(_ image: NSBitmapImageRep, _ path: URL) throws {
        guard let data = image.representation(using: .png, properties: [:]) else { throw Failure(description: "No PNG") }
        try data.write(to: path)
    }

    static func expectPixel(_ image: NSBitmapImageRep, x pointX: CGFloat, y pointY: CGFloat, rgb: UInt32) throws {
        let x = Int((pointX * CGFloat(image.pixelsWide) / image.size.width).rounded(.down))
        let y = Int((pointY * CGFloat(image.pixelsHigh) / image.size.height).rounded(.down))
        guard x >= 0, x < image.pixelsWide, y >= 0, y < image.pixelsHigh,
              let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { throw Failure(description: "Invalid pixel \(x),\(y)") }
        let actual = [color.redComponent, color.greenComponent, color.blueComponent].map { Int(($0 * 255).rounded()) }
        let expected = [Int((rgb >> 16) & 255), Int((rgb >> 8) & 255), Int(rgb & 255)]
        try require(zip(actual, expected).allSatisfy { abs($0 - $1) <= 3 }, "Surface pixel \(x),\(y) was \(actual), expected \(expected)")
    }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(description: message) }
    }
}

private final class BlockedProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}
