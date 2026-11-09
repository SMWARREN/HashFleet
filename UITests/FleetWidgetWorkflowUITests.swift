import XCTest
import UIKit

/// Exercises WidgetKit and SpringBoard on the owned, disposable simulator. The containing
/// app stays alive with private UI-test preferences, so its widget link cannot launch a
/// normal monitoring session or register production background work.
@MainActor
final class FleetWidgetWorkflowUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testInstalledHomeWidgetUsesHashFleetBrandingAndReturnsToTheIsolatedFleet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["dashboard.settingsMenu"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let installed = try installWidget(in: springboard)
        XCTAssertTrue(installed.label.contains("Open the app to connect a miner."))
        attach(springboard, named: "Installed Hash Fleet Home Screen widget")
        try assertTransparentArtwork(on: installed)
        guard app.state == .runningBackground || app.state == .runningBackgroundSuspended else {
            XCTFail("Do not tap a widget that could cold-launch the app without UI-test isolation")
            return
        }
        installed.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.navigationBars["Hash Fleet"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["dashboard.settingsMenu"].waitForExistence(timeout: 5))
        attach(app, named: "Widget link returned to the isolated fleet")
    }

    func testAvailableWidgetArtworkKeepsItsTransparentCorners() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["dashboard.settingsMenu"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        var installed = widget(in: springboard)
        if !installed.waitForExistence(timeout: 3) || !installed.isHittable {
            installed = try installWidget(in: springboard)
        }
        attach(springboard, named: "Installed widget artwork alpha")
        try assertTransparentArtwork(on: installed)
    }

    private func installWidget(in springboard: XCUIApplication) throws -> XCUIElement {
        let priorDone = springboard.buttons["Done"].firstMatch
        if priorDone.exists && priorDone.isHittable { priorDone.tap() }
        let icon = springboard.icons["Hash Fleet"].firstMatch
        XCTAssertTrue(icon.waitForExistence(timeout: 10))
        XCTAssertTrue(icon.isHittable)
        icon.press(forDuration: 1.2)
        try control(named: "Edit Home Screen", in: springboard).tap()
        try control(named: "Edit", in: springboard).tap()
        try control(named: "Add Widget", in: springboard).tap()
        let search = springboard.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Hash Fleet")
        try control(named: "Hash Fleet", in: springboard).tap()
        XCTAssertTrue(springboard.staticTexts["Fleet at a glance"].waitForExistence(timeout: 10))
        XCTAssertFalse(springboard.staticTexts["HashFleet"].exists)
        attach(springboard, named: "Installed Hash Fleet widget gallery")
        // The gallery's plus-image label contributes a leading space in AX.
        // Its Edit menu uses the unprefixed label above.
        try control(named: " Add Widget", in: springboard).tap()
        try control(named: "Done", in: springboard).tap()
        let installed = widget(in: springboard)
        guard installed.waitForExistence(timeout: 15), installed.isHittable else {
            attach(springboard, named: "Installed widget was not readable")
            XCTFail("The installed production widget must expose its honest empty-state summary")
            throw WidgetWorkflowError.missingControl("Installed fleet widget")
        }
        return installed
    }

    private func widget(in springboard: XCUIApplication) -> XCUIElement {
        // Production privacy semantics combine the whole widget into this AX summary.
        // The empty state is expected because this unsigned isolated app never shares data.
        springboard.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "Hash Fleet. No cached fleet.")
        ).firstMatch
    }

    private func assertTransparentArtwork(on widget: XCUIElement) throws {
        let artwork = widget.images["Hash Fleet"].firstMatch
        XCTAssertTrue(artwork.waitForExistence(timeout: 5))
        let screenshot = artwork.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Actual installed brand pixels"
        attachment.lifetime = .keepAlways
        add(attachment)
        let image = try XCTUnwrap(screenshot.image.cgImage)
        XCTAssertGreaterThan(image.width, 4)
        XCTAssertGreaterThan(image.height, 4)
        let pixels = try rgba(image)
        let canvas = try XCTUnwrap(widget.screenshot().image.cgImage)
        let canvasPixels = try rgba(canvas)
        // Top center is plain canvas, outside the rounded corners, artwork and text.
        let reference = Array(canvasPixels[((canvas.width + canvas.width / 2) * 4)..<((canvas.width + canvas.width / 2) * 4 + 3)])
        for (x, y) in [(1, 1), (image.width - 2, 1), (1, image.height - 2), (image.width - 2, image.height - 2)] {
            let offset = (y * image.width + x) * 4
            let rgb = Array(pixels[offset..<(offset + 3)])
            XCTAssertTrue(zip(rgb, reference).allSatisfy { abs(Int($0.0) - Int($0.1)) <= 8 },
                "The installed mark must not acquire an opaque tile. Corner \(x),\(y): \(rgb), canvas: \(reference)")
        }
    }

    private func rgba(_ image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }

    private func control(named label: String, in app: XCUIApplication) throws -> XCUIElement {
        let matches = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label))
        guard matches.firstMatch.waitForExistence(timeout: 10),
              let control = matches.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
            attach(app, named: "Missing system control \(label)")
            XCTFail("Expected a hittable system control named \(label)")
            throw WidgetWorkflowError.missingControl(label)
        }
        return control
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "\(name) accessibility"
        tree.lifetime = .keepAlways
        add(tree)
    }

    private enum WidgetWorkflowError: Error {
        case missingControl(String)
    }
}
