import XCTest
import UIKit

/// Screenshot regions of the dashboard used to compare surfaces across appearance modes.
struct DashboardRegions {
    let marquee: CGRect
    let canvas: CGRect
    let heroSurface: CGRect
    let rate: CGRect
}

/// Appearance switching and theming acceptance tests for HashFleetUITests.
extension HashFleetUITests {
    func testBundledBrandLoopChangesFanPixelsOnTheHeldSplash() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--ui-testing", "--show-launch-splash", "--ui-test-hold-splash"]
        app.launch()

        let splash = app.descendants(matching: .any)["launch.splash"]
        XCTAssertTrue(splash.waitForExistence(timeout: 5))
        let miner = app.images["launch.miner"]
        XCTAssertTrue(miner.waitForExistence(timeout: 5))

        let firstFanCapture = try fanCrop(
            from: app.screenshot().image,
            app: app,
            miner: miner
        )
        Thread.sleep(forTimeInterval: 0.3)
        let secondFanCapture = try fanCrop(
            from: app.screenshot().image,
            app: app,
            miner: miner
        )

        XCTAssertNotEqual(
            firstFanCapture,
            secondFanCapture,
            "The bundled animated WebP should change visible fan pixels while the splash is held"
        )
    }

    func testWelcomeBitsyWavesOnTheEmptyDashboard() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--ui-testing"]
        app.launch()

        XCTAssertTrue(app.buttons["dashboard.connectFirstMiner"].waitForExistence(timeout: 10))
        let bitsy = app.descendants(matching: .any)["onboarding.bitsy"]
        XCTAssertTrue(bitsy.waitForExistence(timeout: 5))
        XCTAssertTrue(bitsy.isHittable)
        XCTAssertGreaterThanOrEqual(bitsy.frame.height, 100, "Bitsy should be a prominent welcome character.")
        XCTAssertTrue(bitsy.label.localizedCaseInsensitiveContains("Bitsy"), bitsy.label)

        // Let the one-shot speech bubble reveal settle, then compare only the character
        // surface so clock/status and unrelated dashboard animations cannot affect the result.
        Thread.sleep(forTimeInterval: 0.9)
        let firstFrame = try elementCrop(from: app.screenshot().image, app: app, element: bitsy)
        Thread.sleep(forTimeInterval: 0.3)
        let secondFrame = try elementCrop(from: app.screenshot().image, app: app, element: bitsy)

        XCTAssertNotEqual(firstFrame, secondFrame, "Bitsy's visible wave should continue in the welcome idle state.")
        recordScreenshot("Welcome Bitsy waving beside its greeting", app: app)
    }

    func testWelcomeBitsyRespectsReduceMotion() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--ui-testing", "--ui-test-reduce-motion"]
        app.launch()

        XCTAssertTrue(app.buttons["dashboard.connectFirstMiner"].waitForExistence(timeout: 10))
        let bitsy = app.descendants(matching: .any)["onboarding.bitsy"]
        XCTAssertTrue(bitsy.waitForExistence(timeout: 5))
        XCTAssertTrue(bitsy.isHittable)

        // Under Reduce Motion, the pose and bubble settle to a stable still image while
        // the character remains visible and its greeting stays available to accessibility.
        Thread.sleep(forTimeInterval: 0.4)
        let firstFrame = try elementCrop(from: app.screenshot().image, app: app, element: bitsy)
        Thread.sleep(forTimeInterval: 0.3)
        let secondFrame = try elementCrop(from: app.screenshot().image, app: app, element: bitsy)

        XCTAssertEqual(firstFrame, secondFrame, "Reduce Motion should stop the looping Bitsy pose.")
        XCTAssertTrue(bitsy.label.localizedCaseInsensitiveContains("Bitsy"), bitsy.label)
        recordScreenshot("Welcome Bitsy still pose with Reduce Motion", app: app)
    }

    func testThreeMinerPictureAutomaticallyKeepsSpinningForAboutTenSeconds() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let cluster = app.descendants(matching: .any)["onboarding.minerCluster"]
        XCTAssertTrue(cluster.waitForExistence(timeout: 5))
        XCTAssertTrue(cluster.isHittable)
        // No tap. The old four-second entrance was already resting at this point.
        Thread.sleep(forTimeInterval: 5)
        let first = try elementCrop(from: app.screenshot().image, app: app, element: cluster)
        Thread.sleep(forTimeInterval: 0.23)
        let second = try elementCrop(from: app.screenshot().image, app: app, element: cluster)
        XCTAssertNotEqual(first, second, "The actual three-miner fan picture must still animate through its ten-second entrance without a tap")
        recordScreenshot("Three-miner picture automatically spinning without a tap", app: app)
        Thread.sleep(forTimeInterval: 5.5)
        let restA = try elementCrop(from: app.screenshot().image, app: app, element: cluster)
        Thread.sleep(forTimeInterval: 0.3)
        let restB = try elementCrop(from: app.screenshot().image, app: app, element: cluster)
        XCTAssertEqual(restA, restB, "The entrance must settle after about ten seconds instead of running indefinitely")
    }

    func testAddMinerUsesTheActualThreeMinerPictureAndReplaysOnEachPresentation() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let add = app.buttons["dashboard.addMiner"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        for presentation in 1...2 {
            add.tap()
            XCTAssertTrue(app.navigationBars["Add a miner"].waitForExistence(timeout: 5))
            let cluster = app.descendants(matching: .any)["addMiner.minerCluster"]
            XCTAssertTrue(cluster.waitForExistence(timeout: 5), "Add Miner must use the literal three-miner artwork, not status badges or a network diagram")
            XCTAssertTrue(cluster.isHittable)
            Thread.sleep(forTimeInterval: 0.25)
            let first = try elementCrop(from: app.screenshot().image, app: app, element: cluster)
            Thread.sleep(forTimeInterval: 0.23)
            let second = try elementCrop(from: app.screenshot().image, app: app, element: cluster)
            XCTAssertNotEqual(first, second, "Opening Add Miner must start the fans without tapping the picture")
            XCTAssertTrue(app.buttons["addMiner.discoveryStart"].exists)
            XCTAssertFalse(app.buttons["addMiner.discoveryCancel"].exists, "Artwork playback must never start network discovery")
            recordScreenshot("Add Miner three-miner picture presentation \(presentation)", app: app)
            app.buttons["addMiner.dismiss"].tap()
            XCTAssertTrue(add.waitForExistence(timeout: 5))
        }
    }

    func testWelcomeMinerFansSpinInBurstsAndOnTap() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--ui-testing"]
        app.launch()

        XCTAssertTrue(app.buttons["dashboard.connectFirstMiner"].waitForExistence(timeout: 10))
        let cluster = app.descendants(matching: .any)["onboarding.minerCluster"]
        XCTAssertTrue(cluster.waitForExistence(timeout: 5))
        XCTAssertTrue(cluster.isHittable, "The three-miner art should be visible with Bitsy without scrolling.")
        XCTAssertGreaterThanOrEqual(cluster.frame.width, 220, "The fans must be large enough to notice.")
        XCTAssertLessThan(cluster.frame.maxY, app.frame.maxY, "The fans must fit on the initial phone screen.")

        // Tapping spins the fans up immediately, so consecutive frames differ.
        cluster.tap()
        Thread.sleep(forTimeInterval: 0.25)
        let spinA = try elementCrop(from: app.screenshot().image, app: app, element: cluster)
        Thread.sleep(forTimeInterval: 0.2)
        let spinB = try elementCrop(from: app.screenshot().image, app: app, element: cluster)
        XCTAssertNotEqual(spinA, spinB, "The miner fans should spin after a tap.")
        recordScreenshot("Welcome miner fans spinning", app: app)

        // After the burst (two ~2 s loops), the fans rest on a still frame.
        Thread.sleep(forTimeInterval: 4.6)
        let restA = try elementCrop(from: app.screenshot().image, app: app, element: cluster)
        Thread.sleep(forTimeInterval: 0.4)
        let restB = try elementCrop(from: app.screenshot().image, app: app, element: cluster)
        XCTAssertEqual(restA, restB, "The miner fans should pause between spin-ups.")
    }

    func testFleetSummaryThreeMinerPictureStartsWithoutATapWhenDemoLoads() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--ui-testing", "--demo"]
        app.launch()

        let cluster = app.descendants(matching: .any)["dashboard.fleetArtwork"]
        XCTAssertTrue(cluster.waitForExistence(timeout: 5))
        XCTAssertTrue(cluster.isHittable)
        Thread.sleep(forTimeInterval: 0.25)
        let first = try elementCrop(from: app.screenshot().image, app: app, element: cluster)
        Thread.sleep(forTimeInterval: 0.23)
        let second = try elementCrop(from: app.screenshot().image, app: app, element: cluster)
        XCTAssertNotEqual(first, second, "The actual fleet-summary picture must start its fans without a tap")
        recordScreenshot("Fleet summary three-miner picture automatically spinning", app: app)
    }

    func testAddMinerThreeMinerPictureStaysStillWithReduceMotion() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--ui-testing", "--ui-test-reduce-motion"]
        app.launch()
        app.buttons["dashboard.addMiner"].tap()
        let cluster = app.descendants(matching: .any)["addMiner.minerCluster"]
        XCTAssertTrue(cluster.waitForExistence(timeout: 5))
        XCTAssertTrue(cluster.isHittable)
        cluster.tap()
        Thread.sleep(forTimeInterval: 0.3)
        let first = try elementCrop(from: app.screenshot().image, app: app, element: cluster)
        Thread.sleep(forTimeInterval: 0.3)
        let second = try elementCrop(from: app.screenshot().image, app: app, element: cluster)
        XCTAssertEqual(first, second, "Reduce Motion keeps the literal picture still, including after a tap")
        XCTAssertFalse(app.buttons["addMiner.discoveryCancel"].exists)
        recordScreenshot("Add Miner three-miner picture with Reduce Motion", app: app)
    }

    func testWelcomeMinerFansStayStillWithReduceMotion() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--ui-testing", "--ui-test-reduce-motion"]
        app.launch()

        XCTAssertTrue(app.buttons["dashboard.connectFirstMiner"].waitForExistence(timeout: 10))
        let cluster = app.descendants(matching: .any)["onboarding.minerCluster"]
        XCTAssertTrue(cluster.waitForExistence(timeout: 5))
        var swipes = 0
        while !cluster.isHittable && swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        cluster.tap()
        Thread.sleep(forTimeInterval: 0.3)
        let first = try elementCrop(from: app.screenshot().image, app: app, element: cluster)
        Thread.sleep(forTimeInterval: 0.4)
        let second = try elementCrop(from: app.screenshot().image, app: app, element: cluster)
        XCTAssertEqual(first, second, "Reduce Motion should keep the miner fans still.")
    }

    func testWelcomeBitsyAndMinerArtStayUsableAtAccessibilityTextSize() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--ui-testing",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()

        let connect = app.buttons["dashboard.connectFirstMiner"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        let bitsy = app.descendants(matching: .any)["onboarding.bitsy"]
        XCTAssertTrue(bitsy.waitForExistence(timeout: 5))
        XCTAssertTrue(bitsy.isHittable, "Bitsy's greeting should be on screen at the largest text size.")
        XCTAssertLessThanOrEqual(bitsy.frame.maxX, app.frame.maxX + 1, "Bitsy's bubble must not clip off screen.")
        XCTAssertTrue(bitsy.label.localizedCaseInsensitiveContains("Bitsy"), bitsy.label)
        var swipes = 0
        while !connect.isHittable && swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(connect.isHittable, "The primary action must remain reachable.")
        let cluster = app.descendants(matching: .any)["onboarding.minerCluster"]
        swipes = 0
        while !(cluster.exists && cluster.isHittable) && swipes < 8 {
            app.swipeDown()
            swipes += 1
        }
        XCTAssertTrue(cluster.isHittable, "The three-miner art should remain reachable.")
        XCTAssertLessThanOrEqual(cluster.frame.maxX, app.frame.maxX + 1, "The miner art must not clip off screen.")
        // The section heading must not be squeezed beside the art into one word per line.
        let heading = app.staticTexts["Start with your local hardware"]
        XCTAssertTrue(heading.exists)
        XCTAssertGreaterThan(heading.frame.width, app.frame.width * 0.6, heading.debugDescription)
        XCTAssertLessThanOrEqual(cluster.frame.maxY, heading.frame.minY + 1,
                                 "At accessibility sizes the art remains above the heading with Bitsy.")
        recordScreenshot("Welcome at Accessibility XXXL", app: app)
    }

    func testInAppAlertBannerShowsOpensMinerAndDismisses() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--demo", "--ui-testing", "--ui-test-in-app-alert"]
        app.launch()

        let banner = app.descendants(matching: .any)["inAppAlert.banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "An open-app alert should appear as an in-app banner.")
        XCTAssertTrue(banner.isHittable)
        XCTAssertTrue(banner.label.localizedCaseInsensitiveContains("offline"), banner.label)
        // The banner must not cover the toolbar: Settings stays tappable while it is shown.
        let settings = app.buttons["dashboard.settingsMenu"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        XCTAssertTrue(settings.isHittable, "The in-app alert must not cover the toolbar.")
        XCTAssertGreaterThanOrEqual(banner.frame.minY, settings.frame.maxY - 1)
        recordScreenshot("In-app alert banner while the app is open", app: app)

        // The dismiss control removes the banner without leaving the dashboard.
        app.buttons["Dismiss alert"].firstMatch.tap()
        XCTAssertFalse(banner.waitForExistence(timeout: 2))
    }

    func testBitsyGuidesPopulatedDemoDashboard() {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--demo", "--ui-testing"]
        app.launch()

        let bitsy = app.descendants(matching: .any)["dashboard.bitsy"]
        XCTAssertTrue(bitsy.waitForExistence(timeout: 10))
        for _ in 0..<12 where !bitsy.isHittable { app.swipeUp() }
        XCTAssertTrue(bitsy.isHittable)
        XCTAssertTrue(bitsy.label.localizedCaseInsensitiveContains("Bitsy"), bitsy.label)
        XCTAssertTrue(bitsy.label.localizedCaseInsensitiveContains("sample miner"), bitsy.label)
        XCTAssertTrue(bitsy.label.localizedCaseInsensitiveContains("never change your hardware"), bitsy.label)
        recordScreenshot("Bitsy guide retained below primary fleet tools", app: app)
        let miners = app.descendants(matching: .any)["dashboard.fleetArtwork"]
        XCTAssertTrue(miners.waitForExistence(timeout: 5), "The populated dashboard also shows three animated miners.")
        for _ in 0..<12 where !miners.isHittable { app.swipeDown() }
        XCTAssertTrue(miners.isHittable)
        recordScreenshot("Compact artwork on the chart-first fleet dashboard", app: app)
    }

    func testPopulatedDashboardThreeMinerFansAnimateOnTap() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--demo", "--ui-testing"]
        app.launch()

        let miners = app.descendants(matching: .any)["dashboard.fleetArtwork"]
        XCTAssertTrue(miners.waitForExistence(timeout: 10))
        XCTAssertTrue(miners.isHittable, "The three miners should be visible on the populated dashboard.")
        miners.tap()
        Thread.sleep(forTimeInterval: 0.25)
        let first = try elementCrop(from: app.screenshot().image, app: app, element: miners)
        Thread.sleep(forTimeInterval: 0.25)
        let second = try elementCrop(from: app.screenshot().image, app: app, element: miners)
        XCTAssertNotEqual(first, second, "The populated dashboard fans should visibly rotate, not be a static picture.")
    }

    func testThemedHashFleetSplashCanBeSkippedAndDoesNotRepeatOnResume() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        for mode in ["Dark", "Light"] {
            app.launchArguments = ["--ui-testing", "--show-launch-splash", "--ui-test-hold-splash"]
            if mode == "Light" { app.launchArguments.append("--ui-test-light-appearance") }
            app.launch()
            let splash = app.descendants(matching: .any)["launch.splash"]
            XCTAssertTrue(splash.waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["launch.wordmark"].exists)
            let miner = app.images["launch.miner"]
            XCTAssertTrue(miner.exists)
            XCTAssertEqual(miner.frame.midX, app.frame.midX, accuracy: 1)
            XCTAssertEqual(miner.frame.midY, app.frame.midY, accuracy: 1)
            XCTAssertEqual(miner.frame.width, 220, accuracy: 1)
            XCTAssertEqual(miner.frame.height, 220, accuracy: 1)
            let splashRegion = CGRect(x: 20, y: app.frame.midY, width: 5, height: 5)
            let background = try sampleRegionRGB(app, in: splashRegion)
            let expectedBackground = mode == "Dark"
                ? RGBSample(r: 2.0 / 255.0, g: 9.0 / 255.0, b: 12.0 / 255.0)
                : RGBSample(r: 1, g: 1, b: 1)
            XCTAssertEqual(background.r, expectedBackground.r, accuracy: 0.03)
            XCTAssertEqual(background.g, expectedBackground.g, accuracy: 0.03)
            XCTAssertEqual(background.b, expectedBackground.b, accuracy: 0.03)
            recordScreenshot("\(mode) mode adaptive logo-only splash", app: app)
            app.buttons["launch.continue"].tap()
            XCTAssertTrue(app.buttons["dashboard.addMiner"].waitForExistence(timeout: 5))
            XCTAssertFalse(splash.exists)
            XCUIDevice.shared.press(.home)
            app.activate()
            XCTAssertTrue(app.buttons["dashboard.addMiner"].waitForExistence(timeout: 5))
            XCTAssertFalse(splash.exists, "Warm foreground activation must not replay the splash")
            app.terminate()
        }
    }

    private func fanCrop(
        from screenshot: UIImage,
        app: XCUIApplication,
        miner: XCUIElement
    ) throws -> Data {
        let screenImage = try XCTUnwrap(screenshot.cgImage)
        let scaleX = CGFloat(screenImage.width) / app.frame.width
        let scaleY = CGFloat(screenImage.height) / app.frame.height
        let fanRegion = CGRect(
            x: miner.frame.midX - 54,
            y: miner.frame.midY - 54,
            width: 108,
            height: 108
        )
        let pixels = CGRect(
            x: fanRegion.minX * scaleX,
            y: fanRegion.minY * scaleY,
            width: fanRegion.width * scaleX,
            height: fanRegion.height * scaleY
        ).integral
        let crop = try XCTUnwrap(screenImage.cropping(to: pixels))
        return try XCTUnwrap(UIImage(cgImage: crop).pngData())
    }

    private func elementCrop(
        from screenshot: UIImage,
        app: XCUIApplication,
        element: XCUIElement
    ) throws -> Data {
        let screenImage = try XCTUnwrap(screenshot.cgImage)
        let visibleFrame = element.frame.intersection(app.frame)
        XCTAssertFalse(visibleFrame.isNull || visibleFrame.isEmpty, "The welcome character must be on screen.")
        let scaleX = CGFloat(screenImage.width) / app.frame.width
        let scaleY = CGFloat(screenImage.height) / app.frame.height
        let pixelFrame = CGRect(
            x: visibleFrame.minX * scaleX,
            y: visibleFrame.minY * scaleY,
            width: visibleFrame.width * scaleX,
            height: visibleFrame.height * scaleY
        ).integral
        let cropFrame = pixelFrame.intersection(CGRect(x: 0, y: 0, width: screenImage.width, height: screenImage.height))
        let crop = try XCTUnwrap(screenImage.cropping(to: cropFrame))
        return try XCTUnwrap(UIImage(cgImage: crop).pngData())
    }
}
