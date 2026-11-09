import XCTest
import UIKit

/// Appearance switching acceptance tests for HashFleetUITests.
extension HashFleetUITests {
    func testSystemAppearanceAndManualOverride() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--ui-testing", "--ui-test-system-appearance"]
        app.launch()
        defer { app.terminate() }
        let appearance = dashboardSettingsMenu(in: app)
        XCTAssertTrue(appearance.waitForExistence(timeout: 10))
        let initial = try XCTUnwrap(appearance.value as? String)
        XCTAssertTrue(["System · Light", "System · Dark"].contains(initial), initial)
        let followsDark = initial == "System · Dark"
        let rate = app.descendants(matching: .any)["dashboard.fleetHashrate"]
        XCTAssertTrue(rate.waitForExistence(timeout: 5))
        let canvasRect = CGRect(x: app.frame.minX + 4, y: rate.frame.midY, width: 6, height: 3)
        let canvas = try sampleRegionRGB(app, in: canvasRect)
        for channel in [canvas.r, canvas.g, canvas.b] {
            // The proposed dark canvas is a near-black graphite, not pure black.
            XCTAssertEqual(channel, followsDark ? 0 : 1, accuracy: followsDark ? 0.06 : 0.025)
        }
        recordScreenshot("System \(followsDark ? "Dark" : "Light") dashboard", app: app)
        let manual = followsDark ? "Light" : "Dark"
        setDashboardAppearance(manual, in: app)
        let changed = expectation(for: NSPredicate(format: "value == %@", manual), evaluatedWith: appearance)
        wait(for: [changed], timeout: 5)
        let overridden = try sampleRegionRGB(app, in: canvasRect)
        XCTAssertEqual(overridden.r, followsDark ? 1 : 0, accuracy: followsDark ? 0.025 : 0.06)

        openFleetSettings(in: app)
        app.buttons["monitoring.fleet"].tap()
        let picker = app.buttons["preferences.appearance"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        let system = app.buttons["System"]
        XCTAssertTrue(system.waitForExistence(timeout: 5))
        system.tap()
        returnToFleet(in: app)
        let restoredPredicate = NSPredicate(format: "value == %@", initial)
        let restored = expectation(for: restoredPredicate, evaluatedWith: appearance)
        wait(for: [restored], timeout: 5)
        XCTAssertEqual(try sampleRegionRGB(app, in: canvasRect).r, canvas.r, accuracy: 0.025)
        recordScreenshot("Restored \(initial)", app: app)
    }

    func testAppearanceSwitchUpdatesDashboardDetailsAndSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--ui-testing"]
        app.launch()
        let appearance = dashboardSettingsMenu(in: app)
        XCTAssertTrue(appearance.waitForExistence(timeout: 10))
        XCTAssertEqual(appearance.value as? String, "Dark")
        recordScreenshot("Black graphite and gold dark dashboard", app: app)

        let regions = try dashboardSampleRegions(in: app)
        let chains = app.descendants(matching: .any)["dashboard.chains"]
        XCTAssertTrue(chains.waitForExistence(timeout: 5))
        let dark = try verifyDarkSurfaces(app: app, regions: regions, chains: chains)

        setDashboardAppearance("Light", in: app)
        XCTAssertEqual(appearance.value as? String, "Light")
        recordScreenshot("White and gold light dashboard", app: app)
        let light = try verifyLightSurfaces(app: app, regions: regions, chains: chains, dark: dark)

        let lightCard = try verifyLightDetailSettingsAndAbout(app: app, lightSummary: light)
        try restoreDarkModeAndVerify(app: app, appearance: appearance, dark: dark, lightCard: lightCard)
    }

    private func dashboardSampleRegions(in app: XCUIApplication) throws -> DashboardRegions {
        let ticker = app.descendants(matching: .any)["fleet.ticker"]
        XCTAssertTrue(ticker.waitForExistence(timeout: 10))
        let marquee = CGRect(x: max(10, ticker.frame.minX + 10), y: ticker.frame.maxY - 3, width: 12, height: 2)
        let hashrate = app.descendants(matching: .any)["dashboard.fleetHashrate"]
        XCTAssertTrue(hashrate.waitForExistence(timeout: 5))
        // Ticker AX bounds exclude some of its padding. The 16pt gutter beside
        // the hashrate card is the actual canvas, not the ticker background.
        let canvas = CGRect(x: app.frame.minX + 4, y: hashrate.frame.midY, width: 6, height: 3)
        let heroSurface = CGRect(x: app.frame.maxX - 65, y: hashrate.frame.midY, width: 12, height: 3)
        return DashboardRegions(marquee: marquee, canvas: canvas,
                                heroSurface: heroSurface, rate: hashrate.frame.insetBy(dx: 1, dy: 1))
    }

    private func summarySample(app: XCUIApplication, card: XCUIElement) throws -> RGBSample {
        let summaryRect = CGRect(x: card.frame.midX, y: card.frame.minY + 5, width: 12, height: 3)
        return try sampleRegionRGB(app, in: summaryRect)
    }

    private struct DarkBaselines {
        let summary: RGBSample
        let marquee: RGBSample
        let canvas: RGBSample
    }

    private func verifyDarkSurfaces(app: XCUIApplication, regions: DashboardRegions,
                                    chains: XCUIElement) throws -> DarkBaselines {
        let darkMarquee = try sampleRegionRGB(app, in: regions.marquee)
        let darkCanvas = try sampleRegionRGB(app, in: regions.canvas)
        let darkHero = try sampleRegionRGB(app, in: regions.heroSurface)
        XCTAssertLessThan(darkHero.r, 0.20, "Dark mode hashrate uses a raised graphite surface, not the canvas")
        XCTAssertGreaterThan(darkHero.r, darkCanvas.r, "The hashrate surface must lift off the dark canvas")
        let darkRateRegion = try sampleRegionRGB(app, in: regions.rate)
        XCTAssertGreaterThan(darkRateRegion.r, darkHero.r + 0.03,
                             "Light ink must remain visible on the dark hashrate surface")
        XCTAssertLessThan(darkMarquee.r, 0.06, "Dark ticker must stay near-black")
        XCTAssertLessThan(darkMarquee.g, 0.08, "Dark ticker must stay near-black")
        XCTAssertLessThan(darkMarquee.b, 0.09, "Dark ticker must stay near-black")
        let darkSummary = try summarySample(app: app, card: chains)
        try assertRestoredSolo(app, card: chains, top: darkSummary)
        XCTAssertLessThan(darkCanvas.r, 0.06, "Dark canvas must start near-black")
        XCTAssertLessThan(darkCanvas.g, 0.08, "Dark canvas must start near-black")
        XCTAssertLessThan(darkCanvas.b, 0.09, "Dark canvas must start near-black")
        return DarkBaselines(summary: darkSummary, marquee: darkMarquee, canvas: darkCanvas)
    }

    private func verifyLightSurfaces(app: XCUIApplication, regions: DashboardRegions,
                                     chains: XCUIElement, dark: DarkBaselines) throws -> RGBSample {
        let lightMarquee = try sampleRegionRGB(app, in: regions.marquee)
        let lightCanvas = try sampleRegionRGB(app, in: regions.canvas)
        let lightHero = try sampleRegionRGB(app, in: regions.heroSurface)
        XCTAssertLessThan(lightHero.r, 0.20, "Light mode hashrate needs a contrasting charcoal surface")
        XCTAssertEqual(lightHero.r, lightHero.g, accuracy: 0.02)
        XCTAssertEqual(lightHero.g, lightHero.b, accuracy: 0.02)
        let lightRateRegion = try sampleRegionRGB(app, in: regions.rate)
        XCTAssertGreaterThan(lightRateRegion.r, lightHero.r + 0.03, "Light ink must remain visible on charcoal")
        XCTAssertGreaterThan(lightMarquee.r, 0.97, "Light marquee must blend into the white page")
        XCTAssertGreaterThan(lightMarquee.g, 0.97, "Light marquee must blend into the white page")
        XCTAssertGreaterThan(lightMarquee.b, 0.97, "Light marquee must blend into the white page")
        XCTAssertGreaterThan(lightCanvas.r, 0.97, "Light canvas must start with clean white")
        XCTAssertGreaterThan(lightCanvas.g, 0.97, "Light canvas must start with clean white")
        XCTAssertGreaterThan(lightCanvas.b, 0.97, "Light canvas must not have a cream tint")
        XCTAssertEqual(lightMarquee.r, lightCanvas.r, accuracy: 0.025, "No separate light marquee background")
        XCTAssertEqual(dark.marquee.r, dark.canvas.r, accuracy: 0.025, "No separate dark marquee background")
        XCTAssertGreaterThan(lightCanvas.r - dark.canvas.r, 0.35,
                             "Canvas background must distinctly differ between modes")
        let lightSummary = try summarySample(app: app, card: chains)
        try assertRestoredSolo(app, card: chains, top: lightSummary)
        XCTAssertEqual(lightSummary.r, 33.0 / 255.0, accuracy: 0.01,
                       "Solo must use slightly lighter blade graphite in light mode")
        return lightSummary
    }

    private func verifyLightDetailSettingsAndAbout(app: XCUIApplication,
                                                   lightSummary: RGBSample) throws -> RGBSample {
        app.buttons["dashboard.addMiner"].tap()
        XCTAssertTrue(app.navigationBars["Add a miner"].waitForExistence(timeout: 5))
        recordScreenshot("White and gold add miner sheet", app: app)
        app.buttons["Cancel"].tap()

        let miner = minerButton(named: "Little Supra", in: app)
        reveal(miner, in: app)
        // The AX link bounds contain the title, not the outer card. Sample its
        // 14pt top padding, centered away from the rounded corners and glyphs.
        let lightCardRect = CGRect(x: miner.frame.midX, y: miner.frame.minY - 9, width: 12, height: 3)
        let lightCard = try sampleRegionRGB(app, in: lightCardRect)
        XCTAssertGreaterThan(lightCard.r, 0.75, "Light miner card surface should be neutral light gray")
        XCTAssertGreaterThan(lightCard.g, 0.70, "Light miner card surface should be neutral light gray")
        XCTAssertLessThan(abs(lightCard.r - lightCard.g), 0.02, "Light cards must remain neutral")
        XCTAssertLessThan(abs(lightCard.g - lightCard.b), 0.02, "Light cards must not have a cream tint")
        XCTAssertEqual(lightCard.r, 229.0 / 255.0, accuracy: 0.025, "Miner cards must use the visible silver layer")
        XCTAssertGreaterThan(lightCard.r - lightSummary.r, 0.75,
                             "Silver miners must contrast with the black comparison panel")
        miner.tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.minerTitle"].waitForExistence(timeout: 5))
        recordScreenshot("White and gold light miner details", app: app)
        app.navigationBars.buttons.firstMatch.tap()

        openFleetSettings(in: app)
        app.buttons["monitoring.fleet"].tap()
        let picker = app.buttons["preferences.appearance"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.label.contains("Light") || (picker.value as? String) == "Light", picker.debugDescription)
        recordScreenshot("White and gold light preferences", app: app)
        returnToFleet(in: app)
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 5))
        // No tab bar in this app shell; the dashboard toolbar menu proves we are back on the fleet.
        XCTAssertTrue(app.buttons["dashboard.settingsMenu"].waitForExistence(timeout: 5))

        openFleetAbout(in: app)
        XCTAssertTrue(app.navigationBars["About Hash Fleet"].waitForExistence(timeout: 5))
        recordScreenshot("White and gold light about form", app: app)
        returnToFleet(in: app)
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 5))
        return lightCard
    }

    private func restoreDarkModeAndVerify(app: XCUIApplication, appearance: XCUIElement,
                                          dark: DarkBaselines, lightCard: RGBSample) throws {
        XCTAssertEqual(appearance.value as? String, "Light")
        setDashboardAppearance("Dark", in: app)
        XCTAssertEqual(appearance.value as? String, "Dark")
        recordScreenshot("Restored logo graphite and gold dark dashboard", app: app)
        let miner = minerButton(named: "Little Supra", in: app)
        reveal(miner, in: app)
        let darkCardRect = CGRect(x: miner.frame.midX, y: miner.frame.minY - 9, width: 12, height: 3)
        let darkCard = try sampleRegionRGB(app, in: darkCardRect)
        XCTAssertLessThan(darkCard.r, 0.50, "Dark miner card surface should be dark graphite")
        XCTAssertLessThan(darkCard.g, 0.50, "Dark miner card surface should be dark graphite")
        XCTAssertGreaterThan(lightCard.r - darkCard.r, 0.30, "Card surface must distinctly differ between modes")
        XCTAssertEqual(darkCard.r, 24.0 / 255.0, accuracy: 0.025, "Miner cards must use the raised graphite layer")
        XCTAssertEqual(dark.summary.r, 33.0 / 255.0, accuracy: 0.01,
                       "Solo keeps its sampled blade graphite in dark mode")
        XCTAssertNotEqual(darkCard.r, dark.summary.r, accuracy: 0.01,
                          "Miner cards must stay distinct from Solo's blade graphite")
        miner.tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.minerTitle"].waitForExistence(timeout: 5))
        recordScreenshot("Gold miner hashrate without border", app: app)
        app.navigationBars.buttons.firstMatch.tap()
        let bestShares = app.descendants(matching: .any)["bestShare.card"]
        reveal(bestShares, in: app)
        XCTAssertTrue(bestShares.exists)
        recordScreenshot("Fleet best shares subtle border", app: app)

        openFleetAbout(in: app)
        XCTAssertTrue(app.navigationBars["About Hash Fleet"].waitForExistence(timeout: 5))
        recordScreenshot("Graphite and gold dark about form", app: app)
        returnToFleet(in: app)
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 5))
    }
}
