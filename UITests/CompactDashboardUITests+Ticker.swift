import XCTest
import UIKit

/// Status ticker motion, pause/resume, pacing, and accessibility coverage for
/// CompactDashboardUITests.
extension CompactDashboardUITests {
    func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        // A previous check may have scrolled beyond this target. Prefer its
        // current direction when AX exposes a frame, then search the other way.
        let frame = element.exists ? element.frame : .zero
        let startsAbove = !frame.isEmpty && frame.midY < app.windows.firstMatch.frame.midY
        for reverse in [false, true] {
            for _ in 0..<12 {
                if element.exists && element.isHittable { return }
                if startsAbove != reverse {
                    app.swipeDown()
                } else {
                    app.swipeUp()
                }
            }
        }
        capture("Unreachable compact acceptance target", app)
        XCTAssertTrue(element.exists && element.isHittable, "Expected reachable element: \(element)")
    }

    func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testStatusTickerCyclesAndPauseReallyStopsSelection() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }
        let pause = app.buttons["fleet.ticker.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(pause.frame.width, 44)
        // AX bounds include the repeated offscreen copies, not the clipped viewport.
        // In this default dark-mode launch, verify light glyphs actually reach the last
        // 8 points before Pause. The previous extra spacer left this region empty.
        var contentReachesPause = false
        for _ in 0..<8 {
            let pixels = try marqueePixels(app, trailingWidth: 8)
            if stride(from: 0, to: pixels.count, by: 4).contains(where: {
                pixels[$0] > 190 && pixels[$0 + 1] > 190 && pixels[$0 + 2] > 190
            }) {
                contentReachesPause = true
                break
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertTrue(contentReachesPause,
                      "Scrolling content should reach within 8pt of the pause hit area")
        let items = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'fleet.ticker.item.'"))
        XCTAssertTrue(items.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(items.count, 3, "The accessible copy should contain every miner exactly once")
        for name in ["Workshop Gamma", "Office Gamma", "Little Supra"] {
            let missingName = "Missing ticker miner: \(name)"
            XCTAssertTrue(items.allElementsBoundByIndex.contains { $0.label.contains(name) }, missingName)
        }
        XCTAssertLessThanOrEqual(items.firstMatch.frame.height, 24, "The normal marquee must remain one text line")
        let firstPixels = try marqueePixels(app)
        Thread.sleep(forTimeInterval: 1.5)
        let movingPixels = try marqueePixels(app)
        XCTAssertGreaterThan(pixelDistance(firstPixels, movingPixels), 0.002,
                             "The actual single-line text should scroll, not just truncate")
        try verifyPauseFreezesAndResume(app: app, pause: pause, items: items)
    }

    func testSevenPoolMarqueeKeepsMovingAcrossConsecutiveSamples() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--pool-icon-demo"]
        app.launch()
        defer { app.terminate() }
        let pause = app.buttons["fleet.ticker.pause"]
        reveal(pause, app)
        XCTAssertTrue(pause.isHittable)
        // A full swipe can overshoot this short strip. Move only the distance needed
        // to center it if reveal left it near the bottom tab bar.
        let excess = pause.frame.midY - app.frame.midY
        if excess > 0 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -min(excess, 250))))
        }
        XCTAssertTrue(pause.isHittable)
        var previous = try marqueePixels(app)
        for sample in 0..<12 {
            Thread.sleep(forTimeInterval: 0.2)
            let next = try marqueePixels(app)
            XCTAssertGreaterThan(pixelDistance(previous, next), 0.002,
                                 "Ticker stalled between consecutive samples \(sample) and \(sample + 1)")
            previous = next
        }
        capture("Seven-pool marquee after consecutive motion samples", app)
    }

    func testFramePacingOptInTracksScreensAndCanBeDisabled() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["performance.overlay"].exists)
        openFleetSettings(in: app)
        let diagnostics = app.buttons["monitoring.performance"]
        reveal(diagnostics, app)
        diagnostics.tap()
        let enabled = app.switches["performance.enabled"]
        XCTAssertTrue(enabled.waitForExistence(timeout: 5))
        enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: enabled)
        waitForExpectations(timeout: 5)
        let screen = app.descendants(matching: .any).matching(identifier: "performance.overlay").firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 5))
        returnToFleet(in: app)
        expectation(for: NSPredicate(format: "label CONTAINS 'Fleet'"), evaluatedWith: screen)
        waitForExpectations(timeout: 5)
        Thread.sleep(forTimeInterval: 2)
        capture("Fleet measured callback pacing", app)
        let miner = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.'")).firstMatch
        reveal(miner, app)
        miner.tap()
        expectation(for: NSPredicate(format: "label CONTAINS 'Miner'"), evaluatedWith: screen)
        waitForExpectations(timeout: 5)
        Thread.sleep(forTimeInterval: 2)
        capture("Miner measured callback pacing", app)
        returnToFleet(in: app)
        openFleetAbout(in: app)
        expectation(for: NSPredicate(format: "label CONTAINS 'About'"), evaluatedWith: screen)
        waitForExpectations(timeout: 5)
        Thread.sleep(forTimeInterval: 2)
        openFleetSettings(in: app)
        XCTAssertTrue(enabled.waitForExistence(timeout: 5))
        for name in ["Fleet", "Miner", "About"] {
            let report = app.descendants(matching: .any)["performance.report.\(name)"]
            reveal(report, app)
            XCTAssertTrue(report.exists, "Expected measured session report for \(name)")
        }
        capture("Per-screen local timing reports", app)
        for _ in 0..<8 where !enabled.isHittable { app.swipeDown() }
        enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertFalse(app.descendants(matching: .any)["performance.overlay"].exists)
    }

    func testSoloComparisonListsEveryCurrentlyMinedDemoCoin() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo", "--pool-icon-demo"]
        app.launch()
        defer { app.terminate() }
        for ticker in ["BTC", "BCH", "BC2", "BCH2", "XEC", "DGB"] {
            let row = app.descendants(matching: .any)["dashboard.chain.\(ticker)"]
            reveal(row, app)
            XCTAssertTrue(row.label.contains(ticker), row.label)
            if !["BTC", "BCH"].contains(ticker) {
                XCTAssertFalse(row.label.contains("1 in"), "Unsupported difficulty must not use another chain's odds")
            }
        }
        capture("Solo comparison follows all currently mined demo coins", app)
    }

    func testAccessibilityTickerExposesStaticUntruncatedMinerSummaries() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--demo",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["fleet.ticker.pause"].exists)
        let items = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'fleet.ticker.item.'"))
        XCTAssertEqual(items.count, 3)
        for item in items.allElementsBoundByIndex {
            XCTAssertTrue(item.label.contains("Simulated"))
            XCTAssertTrue(item.label.contains("Best"))
            XCTAssertTrue(item.label.contains("Accepted"))
        }
        capture("Static accessible ticker", app)
    }

    private func verifyPauseFreezesAndResume(app: XCUIApplication, pause: XCUIElement,
                                             items: XCUIElementQuery) throws {
        pause.tap()
        XCTAssertEqual(pause.label, "Resume status ticker")
        let pausedImage = items.firstMatch.screenshot()
        let pausedAttachment = XCTAttachment(screenshot: pausedImage)
        pausedAttachment.name = "Pause start"
        pausedAttachment.lifetime = .keepAlways
        add(pausedAttachment)
        let pausedPixels = try marqueePixels(app, attachmentName: "Paused viewport start")
        Thread.sleep(forTimeInterval: 5)
        let stillImage = items.firstMatch.screenshot()
        let stillAttachment = XCTAttachment(screenshot: stillImage)
        stillAttachment.name = "Pause after five seconds"
        stillAttachment.lifetime = .keepAlways
        add(stillAttachment)
        let stillPixels = try marqueePixels(app, attachmentName: "Paused viewport after five seconds")
        XCTAssertLessThan(pixelDistance(pausedPixels, stillPixels), 0.002,
                          "Pause must freeze the visible text offset as well as miner selection")
        capture("Paused native ticker", app)
        pause.tap()
        XCTAssertEqual(pause.label, "Pause status ticker")
        Thread.sleep(forTimeInterval: 1.5)
        let resumedPixels = try marqueePixels(app)
        XCTAssertGreaterThan(pixelDistance(stillPixels, resumedPixels), 0.002,
                             "Resuming should restart the visible marquee offset")
    }

    /// SwiftUI's combined AX row bounds extend over the neighboring pause symbol. Crop the
    /// actual text viewport from the screen, excluding that independently animated control.
    private func marqueePixels(_ app: XCUIApplication, trailingWidth: CGFloat? = nil,
                               attachmentName: String? = nil) throws -> [UInt8] {
        let image = try XCTUnwrap(app.screenshot().image.cgImage)
        let scale = CGFloat(image.width) / app.frame.width
        let marquee = app.descendants(matching: .any)["fleet.ticker.marquee"]
        XCTAssertTrue(marquee.exists, "The marquee must expose a stable viewport for acceptance")
        let pause = app.buttons["fleet.ticker.pause"]
        let right = min(pause.frame.minX, app.frame.maxX)
        let left = trailingWidth.map { max(app.frame.minX, right - $0) } ?? app.frame.minX
        let viewport = CGRect(x: left, y: marquee.frame.minY, width: right - left,
                              height: marquee.frame.height).intersection(app.frame)
        let pixels = CGRect(x: viewport.minX * scale, y: viewport.minY * scale,
                            width: viewport.width * scale, height: viewport.height * scale).integral
        let crop = try XCTUnwrap(image.cropping(to: pixels))
        if let attachmentName {
            let attachment = XCTAttachment(image: UIImage(cgImage: crop))
            attachment.name = attachmentName
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        var rgba = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        try rgba.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress,
                width: crop.width,
                height: crop.height,
                bitsPerComponent: 8,
                bytesPerRow: crop.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        }
        return rgba
    }

    private func pixelDistance(_ first: [UInt8], _ second: [UInt8]) -> Double {
        guard first.count == second.count, !first.isEmpty else { return 1 }
        let total = zip(first, second).reduce(0) { partial, pair in
            partial + abs(Int(pair.0) - Int(pair.1))
        }
        return Double(total) / Double(first.count * 255)
    }
}
