import Foundation
import SwiftUI
import Testing
import UIKit
import ImageIO
import Observation
import HashFleetCore
@testable import HashFleet

/// Normal scrolling viewports, not stretched full-page marketing captures.
@Suite("Information Page Viewports", .serialized)
@MainActor
struct FleetInformationPageViewportTests {
    @Test("Presented screenshots detect a deliberately moving control")
    func screenshotMotionNegativeControl() async throws {
        let motion = FleetInformationMotionControl()
        _ = try await FleetViewRenderHarness.render(
            FleetInformationMotionProbe(motion: motion), inspection: { view in
                let before = try await FleetViewRenderHarness.capture(view, named: "motion-probe-before.png")
                // Arm the real animation only after its baseline pixels are captured
                // and recognized. OCR latency must not consume part of the movement.
                motion.start()
                try await Task.sleep(for: .seconds(3.2))
                let after = try await FleetViewRenderHarness.capture(view, named: "motion-probe-after.png")
                #expect(before.pngData != after.pngData)
                let firstWord = try #require(before.recognition.words.first { $0.text == "Moving" })
                let lastWord = try #require(after.recognition.words.first { $0.text == "Moving" })
                #expect(lastWord.bounds.minY - firstWord.bounds.minY > 20)
            }
        )
    }

    @Test("About stays still and returns to the same header after scrolling",
          arguments: ["375x812", "430x932", "932x430", "768x1024"])
    func aboutViewport(_ dimensions: String) async throws {
        let size = viewport(dimensions)
        let fixture = try FleetRenderFixture(demo: false)
        defer { fixture.cleanup() }
        try #require(!UIAccessibility.isReduceMotionEnabled, "Stability must be checked with system motion enabled")
        _ = try await FleetViewRenderHarness.render(
            NavigationStack { AboutView(store: fixture.store) },
            width: size.width, height: size.height,
            readiness: { $0.recognizes("Your hash. Your hardware.") },
            inspection: { view in
                let first = try await FleetViewRenderHarness.capture(view, named: "about-\(dimensions)-initial.png")
                #expect(first.recognizes("devices running ESP-Miner.", allowingLineWraps: true))
                try await Task.sleep(for: .seconds(3.2))
                let idle = try await FleetViewRenderHarness.capture(view, named: "about-\(dimensions)-idle.png")
                // iOS glass chrome can change its edge dithering even when geometry is static.
                // Compare every decoded pixel below the actual navigation bar, not PNG encoding
                // or the system-owned Done button. The deliberately moving probe stays unmasked.
                let bar = try #require(navigationBar(in: view))
                let contentTop = bar.convert(bar.bounds, to: view).maxY + 8
                #expect(try contentPixels(first, below: contentTop) == contentPixels(idle, below: contentTop),
                        "Informational page content must not animate while idle")
                let scroll = try #require(verticalScrollView(in: view))
                let initialOffset = scroll.contentOffset
                for _ in 0..<3 {
                    scroll.setContentOffset(CGPoint(x: 0, y: maximumOffset(scroll)), animated: false)
                    view.layoutIfNeeded()
                    await Task.yield()
                }
                let bottom = try await FleetViewRenderHarness.capture(view, named: "about-\(dimensions)-bottom.png")
                #expect(bottom.recognizes("GPL-3.0"))
                scroll.setContentOffset(initialOffset, animated: false)
                view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(100))
                let returned = try await FleetViewRenderHarness.capture(view, named: "about-\(dimensions)-returned.png")
                let before = try #require(first.recognition.words.first { $0.text == "Your" })
                let after = try #require(returned.recognition.words.first { $0.text == "Your" })
                #expect(abs(before.bounds.minY - after.bounds.minY) <= 2)
                #expect(abs(before.bounds.minX - after.bounds.minX) <= 2)
                #expect(returned.recognizes("devices running ESP-Miner.", allowingLineWraps: true))
            }
        )
    }

    @Test("Support currency controls remain readable through normal scrolling",
          arguments: ["375x812", "430x932", "932x430", "768x1024"])
    func supportViewport(_ dimensions: String) async throws {
        try await inspectSupport(dimensions, category: .large)
    }

    @Test("Large text grows naturally without compressing address rows")
    func supportAccessibilityViewport() async throws {
        try await inspectSupport("390x844", category: .accessibility3)
    }

    @Test("Storefront lookup starts even when the Support section is offscreen")
    func supportLookupIsOwnedByPage() async throws {
        var lookups = 0
        let availability = DeveloperSupportAvailability(currentCountryCode: {
            lookups += 1
            return "USA"
        })
        _ = try await FleetViewRenderHarness.render(
            NavigationStack { DeveloperSupportView(availability: availability) }
                .environment(\.scenePhase, .active)
                .dynamicTypeSize(.accessibility3),
            width: 375, height: 430,
            readiness: { $0.recognizes("Independent.") },
            inspection: { _ in
                for _ in 0..<50 where !availability.isResolved {
                    try await Task.sleep(for: .milliseconds(20))
                }
                #expect(lookups == 1)
                #expect(availability.isResolved)
                #expect(availability.cryptoDestinations.count == 3)
            }
        )
    }

    private func inspectSupport(_ dimensions: String, category: DynamicTypeSize) async throws {
        let size = viewport(dimensions)
        let availability = DeveloperSupportAvailability(currentCountryCode: { "USA" })
        _ = try await FleetViewRenderHarness.render(
            NavigationStack { DeveloperSupportView(availability: availability) }
                .environment(\.scenePhase, .active)
                .dynamicTypeSize(category),
            width: size.width, height: size.height,
            // Capture the actual initial viewport before scrolling to each currency.
            // A separate regression verifies page-owned lookup before the lazy section mounts.
            readiness: { $0.recognizes("Independent.") },
            inspection: { view in
                let scroll = try #require(verticalScrollView(in: view))
                var observed: Set<String> = []
                var reachedBottom = false
                for page in 0..<16 {
                    let capture = try await FleetViewRenderHarness.capture(
                        view, named: "support-\(dimensions)-\(category)-page-\(page).png")
                    for currency in ["BTC", "ETH", "SOL"] {
                        // The visible label may naturally wrap at accessibility sizes.
                        // Require adjacent currency/address words from actual OCR, without
                        // assuming they share a baseline or correcting Vision output.
                        let hasControl = capture.recognizes("\(currency) address", allowingLineWraps: true)
                        if hasControl { observed.insert(currency) }
                    }
                    let maximum = maximumOffset(scroll)
                    if scroll.contentOffset.y >= maximum - 1 {
                        reachedBottom = true
                        if observed == Set(["BTC", "ETH", "SOL"]) { break }
                        // Allow newly visible rows to finish mounting, then observe pixels again.
                        try await Task.sleep(for: .milliseconds(40))
                    }
                    scroll.setContentOffset(CGPoint(x: 0, y: min(maximum, scroll.contentOffset.y + size.height * 0.55)), animated: false)
                    view.layoutIfNeeded()
                    await Task.yield()
                }
                #expect(reachedBottom, "Every currency must be reachable with ordinary scrolling")
                #expect(observed == Set(["BTC", "ETH", "SOL"]))
            }
        )
    }

    private func viewport(_ dimensions: String) -> CGSize {
        let values = dimensions.split(separator: "x").compactMap { Double($0) }
        return CGSize(width: values[0], height: values[1])
    }

    private func verticalScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView {
            return scroll
        }
        return view.subviews.lazy.compactMap { verticalScrollView(in: $0) }.first
    }

    private func navigationBar(in view: UIView) -> UINavigationBar? {
        if let bar = view as? UINavigationBar { return bar }
        return view.subviews.lazy.compactMap { navigationBar(in: $0) }.first
    }

    private func contentPixels(_ capture: FleetRenderedView, below top: CGFloat) throws -> Data {
        let source = try #require(CGImageSourceCreateWithData(capture.pngData as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let y = Int(ceil(top * CGFloat(image.height) / capture.size.height))
        let crop = try #require(image.cropping(to: CGRect(x: 0, y: y, width: image.width, height: image.height - y)))
        return try #require(crop.dataProvider?.data) as Data
    }

    private func maximumOffset(_ scroll: UIScrollView) -> CGFloat {
        max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
    }
}

@MainActor
@Observable
private final class FleetInformationMotionControl {
    private(set) var moved = false

    func start() {
        withAnimation(.linear(duration: 0.5)) { moved = true }
    }
}

private struct FleetInformationMotionProbe: View {
    let motion: FleetInformationMotionControl

    var body: some View {
        Text("Moving screenshot control")
            .font(.system(size: 22))
            .foregroundStyle(.white)
            .offset(y: motion.moved ? 40 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
    }
}

struct FleetObservationTimingHarnessTests {
    @Test func slowRecognitionCannotExpireAnEarlyPixelObservation() {
        let start = ContinuousClock.now
        let window = FleetRenderReadinessWindow(startedAt: start)
        let earlyPixels = start.advanced(by: .milliseconds(100))
        let analysisFinished = start.advanced(by: .seconds(5))
        #expect(!window.isExhausted(by: earlyPixels))
        #expect(window.isExhausted(by: analysisFinished))
    }

    @Test func anUnmetObservationAtTheOriginalDeadlineExhaustsTheWindow() {
        let start = ContinuousClock.now
        let window = FleetRenderReadinessWindow(startedAt: start)
        #expect(!window.isExhausted(by: start.advanced(by: .milliseconds(2_999))))
        #expect(window.isExhausted(by: start.advanced(by: .seconds(3))))
        #expect(window.isExhausted(by: start.advanced(by: .seconds(4))))
    }
}

@Suite(.serialized)
@MainActor
struct FleetMotionProbeHarnessTests {
    @Test func delayedBaselineRemainsStillUntilTheProbeIsArmed() async throws {
        let motion = FleetInformationMotionControl()
        _ = try await FleetViewRenderHarness.render(
            FleetInformationMotionProbe(motion: motion), inspection: { view in
                let first = try await FleetViewRenderHarness.capture(view, named: "unarmed-probe-first.png")
                try await Task.sleep(for: .seconds(3.2))
                let baseline = try await FleetViewRenderHarness.capture(view, named: "unarmed-probe-delayed.png")
                #expect(!motion.moved)
                let initialWord = try #require(first.recognition.words.first { $0.text == "Moving" })
                let baselineWord = try #require(baseline.recognition.words.first { $0.text == "Moving" })
                #expect(abs(baselineWord.bounds.minY - initialWord.bounds.minY) <= 2)
                motion.start()
                try await Task.sleep(for: .seconds(3.2))
                let moved = try await FleetViewRenderHarness.capture(view, named: "armed-probe-moved.png")
                let movedWord = try #require(moved.recognition.words.first { $0.text == "Moving" })
                #expect(movedWord.bounds.minY - baselineWord.bounds.minY > 20)
            })
    }
}

/// Supplemental mounted checks use isolated preferences and a URLSession that cannot reach a server.
@Suite("Fleet Supplemental Rendering Coverage", .serialized)
@MainActor
struct FleetSupplementalRenderingCoverageTests {
    @Test("About page renders privacy and safe-operation guidance")
    func aboutPagePrivacyGuidance() async throws {
        let fixture = try FleetRenderFixture(demo: false)
        defer { fixture.cleanup() }

        let rendered = try await FleetViewRenderHarness.render(NavigationStack {
            AboutView(store: fixture.store)
        }, width: 390, height: 1500)

        #expect(rendered.pngData.count > 0 && rendered.pixelVariation > 1)
        #expect(rendered.visibleText.contains("About Hash Fleet"))
        #expect(rendered.visibleText.contains("Your hash. Your hardware."))
        #expect(rendered.visibleText.contains("No Hash Fleet account or analytics"))
        #expect(rendered.visibleText.contains("Never expose its API directly to the internet."))
        #expect(rendered.recognizes("Support Hash Fleet"))
        #expect(!rendered.recognizes("Copy BTC address"))
        #expect(!rendered.recognizes("Leave an optional tip via PayPal"))
    }

    @Test("Support keeps separate readable currency rows on phone and tablet", arguments: [375, 430, 768])
    func supportCurrencyRows(width: Int) async throws {
        let availability = DeveloperSupportAvailability(currentCountryCode: { "USA" })
        let rendered = try await FleetViewRenderHarness.render(
            NavigationStack { DeveloperSupportView(availability: availability) }
                .environment(\.scenePhase, .active),
            width: CGFloat(width), height: 1800,
            readiness: { $0.recognizes("Copy SOL address") }
        )

        #expect(rendered.pixelVariation > 1)
        #expect(rendered.recognizes("Bitcoin (BTC)"))
        #expect(rendered.recognizes("Ethereum (ETH)"))
        #expect(rendered.recognizes("Solana (SOL)"))
        // Vision occasionally reads the 'y' in Copy as Cyrillic. Its uncorrected
        // word boxes still independently locate each currency beside 'address'.
        // Boxes are PNG pixels, whereas the mounted viewport dimensions are points.
        let image = try #require(UIImage(data: rendered.pngData))
        let scale = image.size.width / CGFloat(width)
        let copyLines = ["BTC", "ETH", "SOL"].compactMap { currency in
            rendered.recognition.words.first { word in
                word.text == currency && rendered.recognition.words.contains { other in
                    other.text == "address" && other.bounds.minX > word.bounds.maxX
                        && abs(other.bounds.midY - word.bounds.midY) < word.bounds.height * 0.5
                }
            }
        }
        #expect(copyLines.count == 3)
        if copyLines.count == 3 {
            #expect(copyLines[1].bounds.minY - copyLines[0].bounds.maxY > 40 * scale)
            #expect(copyLines[2].bounds.minY - copyLines[1].bounds.maxY > 40 * scale)
            #expect(copyLines.allSatisfy { $0.bounds.minX >= 0 && $0.bounds.maxX <= image.size.width })
        }
    }

    @Test("Support unavailable message remains readable without payment controls")
    func supportUnavailableLayout() async throws {
        let availability = DeveloperSupportAvailability(currentCountryCode: { "CAN" })
        let rendered = try await FleetViewRenderHarness.render(
            NavigationStack { DeveloperSupportView(availability: availability) }
                .environment(\.scenePhase, .active),
            width: 375, height: 1000,
            readiness: { $0.recognizes("Thank you for being here") }
        )
        #expect(rendered.recognizes("External tipping isn't available for your current storefront."))
        #expect(!rendered.recognizes("Copy BTC address"))
        #expect(!rendered.recognizes("Leave an optional tip via PayPal"))
    }

    @Test("Backup page renders privacy boundary and demo export restriction")
    func backupPageDemoRestriction() async throws {
        let fixture = try FleetRenderFixture(demo: true)
        defer { fixture.cleanup() }

        let rendered = try await FleetViewRenderHarness.render(NavigationStack {
            FleetBackupView(store: fixture.store)
        }, width: 390, height: 900)

        #expect(rendered.pngData.count > 0 && rendered.pixelVariation > 1)
        #expect(rendered.visibleText.contains("Backup & restore"))
        #expect(rendered.visibleText.contains("Back up your fleet"))
        #expect(rendered.visibleText.contains("Backups include private local miner addresses and names."))
        #expect(rendered.visibleText.contains("Export fleet backup"))
        #expect(rendered.visibleText.contains("Export is unavailable in demo mode."))
        #expect(rendered.visibleText.contains("Import fleet backup"))
    }

    @Test("Empty achievements page renders its first-milestone guidance without opening the persistent database")
    func emptyAchievementsPage() async throws {
        // With no devices, loadAchievements creates an empty task group. Its database query inside
        // the per-device loop is never reached, so MinerTelemetryDatabase.shared is not initialized.
        let fixture = try FleetRenderFixture(demo: false)
        defer { fixture.cleanup() }
        let rendered = try await FleetViewRenderHarness.render(NavigationStack {
            MiningAchievementsView(devices: [])
        }, width: 390, height: 900)

        #expect(rendered.pngData.count > 0 && rendered.pixelVariation > 1)
        #expect(rendered.visibleText.contains("Mining Achievements"))
        #expect(rendered.visibleText.contains("No achievements yet"))
        #expect(rendered.visibleText.contains("Your mining milestones will appear here."))
        #expect(rendered.visibleText.contains("Blocks found and best shares are tracked automatically."))
    }

    @Test("Solo outcome helper renders a source-verified current difficulty and fleet scope")
    func soloOutcomesView() async throws {
        let fixture = try FleetRenderFixture(demo: true)
        defer { fixture.cleanup() }
        let now = Date()
        let mining = MiningDataResult(
            value: BitcoinMiningStatistics(hashrateHPS: 1.0e20, difficulty: 800_000_000_000),
            fetchedAt: now,
            sourceURL: MiningInsightsEndpoint.mining.url
        )
        let failedFees = MiningDataResult<BitcoinFeeRecommendations>(
            error: .network(code: -1009), fetchedAt: now, sourceURL: MiningInsightsEndpoint.fees.url
        )
        let failedBacklog = MiningDataResult<MempoolBacklog>(
            error: .network(code: -1009), fetchedAt: now, sourceURL: MiningInsightsEndpoint.backlog.url
        )
        let failedTip = MiningDataResult<Int>(
            error: .network(code: -1009), fetchedAt: now, sourceURL: MiningInsightsEndpoint.tipHeight.url
        )
        let failedPrice = MiningDataResult<BitcoinPrice>(
            error: .network(code: -1009), fetchedAt: now, sourceURL: MiningInsightsEndpoint.price.url
        )
        let snapshot = NetworkSnapshot(
            fetchedAt: now, fees: failedFees, backlog: failedBacklog, tipHeight: failedTip,
            mining: mining, price: failedPrice
        )
        let view = NetworkInsightsView(fleet: fixture.store, insights: fixture.insights)

        let rendered = try await FleetViewRenderHarness.render(
            view.soloCard(snapshot, now: now), width: 390, height: 700
        )

        #expect(rendered.pngData.count > 0 && rendered.pixelVariation > 1)
        #expect(rendered.visibleText.contains("Solo mining"))
        #expect(rendered.visibleText.contains("outcomes by hashrate"))
        #expect(rendered.visibleText.contains("Bitcoin block odds shown for the selected reported hashrate."))
        #expect(rendered.visibleText.contains("Whole online fleet"))
        #expect(rendered.visibleText.contains("1 day"))
        #expect(rendered.visibleText.contains("These are probability estimates, not countdowns, earnings forecasts or guarantees."))
    }
}
