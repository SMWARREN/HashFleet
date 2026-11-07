import XCTest

/// Averaged red, green, and blue channel values sampled from a screenshot region.
struct RGBSample {
    var r, g, b: Double
}

/// Element settling, scrolling, screenshot capture, and pixel sampling helpers for HashFleetUITests.
extension HashFleetUITests {
    func waitForStableFrame(_ element: XCUIElement) {
        var previous = element.frame
        var stableSince = Date()
        let settled = NSPredicate { _, _ in
            let current = element.frame
            if current != previous {
                previous = current
                stableSince = Date()
                return false
            }
            return element.isHittable && Date().timeIntervalSince(stableSince) >= 0.5
        }
        let expectation = XCTNSPredicateExpectation(predicate: settled, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       "The miner must stop scrolling before its details link is tapped")
    }

    func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        if app.navigationBars["Frequency & voltage"].exists {
            revealFleetControl(element, in: app)
            return
        }
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            if element.exists && element.frame.maxY < app.frame.midY {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(element.exists && element.isHittable, "Expected reachable element: \(element)")
    }

    /// Retained for existing call sites. Delegates to the shared navigation helper so there is a
    /// single definition of how Settings is reached.
    func openSettings(in app: XCUIApplication) {
        openFleetSettings(in: app)
    }

    func openAbout(in app: XCUIApplication) {
        openFleetAbout(in: app)
    }

    func recordScreenshot(_ name: String, app: XCUIApplication) {
        // Navigation elements exist during the native push animation. Let that
        // transition settle so documentation does not capture an intermediate frame.
        Thread.sleep(forTimeInterval: 1)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func minerButton(named name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.miner.' AND label CONTAINS %@", name))
            .firstMatch
    }

    func assertRestoredSolo(_ app: XCUIApplication, card: XCUIElement, top: RGBSample) throws {
        XCTAssertEqual(card.frame.width, app.frame.width - 32, accuracy: 1, "Solo must restore its 16pt side margins")
        XCTAssertEqual(card.frame.midX, app.frame.midX, accuracy: 1)
        XCTAssertEqual(top.r, 33.0 / 255.0, accuracy: 0.005, "Solo must retain the established blade graphite palette")
        XCTAssertEqual(top.g, 32.0 / 255.0, accuracy: 0.005)
        XCTAssertEqual(top.b, 30.0 / 255.0, accuracy: 0.005, "Solo must not introduce a blue tint")
        let cornerRect = CGRect(x: card.frame.minX + 1, y: card.frame.minY + 1, width: 2, height: 2)
        let corner = try sampleRegionRGB(app, in: cornerRect)
        XCTAssertTrue(corner.r < 0.025 || corner.r > 0.97, "Rounded corners must reveal the page canvas")
        let bottomRect = CGRect(x: card.frame.midX, y: card.frame.maxY - 6, width: 12, height: 3)
        let bottom = try sampleRegionRGB(app, in: bottomRect)
        XCTAssertEqual(bottom.r, top.r, accuracy: 0.02, "Solo must remain flat, without an orange gradient")
        XCTAssertEqual(bottom.g, top.g, accuracy: 0.02)
        XCTAssertEqual(bottom.b, top.b, accuracy: 0.02)
    }

    func sampleRegionRGB(_ app: XCUIApplication, in rect: CGRect) throws -> RGBSample {
        let screenshot = app.screenshot()
        let cgImage = try XCTUnwrap(screenshot.image.cgImage, "Expected screenshot to supply a CGImage")
        let scale = CGFloat(cgImage.width) / app.frame.width
        let imageBounds = CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        let pixelRect = CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral.intersection(imageBounds)
        XCTAssertGreaterThanOrEqual(pixelRect.width, 1, "Sample region width must be at least 1 pixel")
        XCTAssertGreaterThanOrEqual(pixelRect.height, 1, "Sample region height must be at least 1 pixel")
        let width = Int(pixelRect.width)
        let height = Int(pixelRect.height)
        let crop = try XCTUnwrap(cgImage.cropping(to: pixelRect), "Expected successful crop of region: \(pixelRect)")
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB), "Expected sRGB color space")
        try rgba.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ), "Expected CGContext creation for pixel sample")
            context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var totalR: Double = 0
        var totalG: Double = 0
        var totalB: Double = 0
        let count = Double(width * height)
        for pixel in 0..<width * height {
            totalR += Double(rgba[pixel * 4])
            totalG += Double(rgba[pixel * 4 + 1])
            totalB += Double(rgba[pixel * 4 + 2])
        }
        return RGBSample(r: totalR / (count * 255.0), g: totalG / (count * 255.0), b: totalB / (count * 255.0))
    }
}
