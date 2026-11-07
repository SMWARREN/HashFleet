import XCTest

/// iOS 27's native Section menu presents the same visible button without forwarding its
/// SwiftUI identifier. Match that exact public label too, never a hidden/test-only route.
@MainActor
func fleetTuningSessionMenuItem(in app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@",
        "dashboard.card.tuningSession", "Frequency & voltage")).firstMatch
}

/// Existing dial workflows select Advanced explicitly. Easy is the public default.
@MainActor
func selectAdvancedTuningControls(in app: XCUIApplication) {
    let modes = app.segmentedControls["tuningSession.controlMode"]
    XCTAssertTrue(modes.waitForExistence(timeout: 5))
    revealFleetControl(modes, in: app)
    modes.buttons["Advanced"].tap()
    XCTAssertTrue(app.buttons["tuningSession.master.plus10"].waitForExistence(timeout: 5))
}

/// Scrolls through the public interface without accidentally changing a tuning dial.
/// Both dashboard and unified-workspace tests use the same strict viewport check.
@MainActor
func revealFleetControl(_ element: XCUIElement, in app: XCUIApplication, requireHittable: Bool = true) {
    let appFrame = app.frame
    let top = app.navigationBars.firstMatch.frame.maxY + 4
    let tabBar = app.tabBars.firstMatch
    let bottom = tabBar.exists ? tabBar.frame.minY - 4 : appFrame.maxY - 24
    let viewport = CGRect(x: appFrame.minX, y: top, width: appFrame.width, height: bottom - top)
    var previousFrame: CGRect?
    var stationaryAttempts = 0
    for attempt in 0..<24 {
        let frame = element.exists ? element.frame : .zero
        stationaryAttempts = frame == previousFrame ? stationaryAttempts + 1 : 0
        previousFrame = frame
        // A hittable element can still be clipped by navigation or the dashboard tab bar.
        if !frame.isEmpty && viewport.contains(frame) && (!requireHittable || element.isHittable) { return }
        let isAboveViewport = !frame.isEmpty && frame.minY < top
        // Start on visible content between the gauges. A hole in a dial's hit shape
        // is not necessarily a scroll hit target, so exclude the entire artwork frame.
        let dials = ["tuningSession.master.dial", "tuningSession.voltage.dial"].compactMap { identifier -> CGRect? in
            let dial = app.descendants(matching: .any)[identifier]
            return dial.exists && !dial.frame.isEmpty ? dial.frame : nil
        }
        let candidateFractions: [CGFloat] = isAboveViewport
            ? [0.3, 0.4, 0.5, 0.6, 0.2, 0.7, 0.8, 0.15, 0.85]
            : [0.7, 0.6, 0.5, 0.4, 0.8, 0.3, 0.2, 0.85, 0.15]
        let startPoints = candidateFractions.map {
            CGPoint(x: viewport.midX, y: viewport.minY + viewport.height * $0)
        }.filter { point in
            !dials.contains { $0.insetBy(dx: -32, dy: -32).contains(point) }
        }
        guard !startPoints.isEmpty else {
            XCTFail("No visible scroll starting point outside the dial rims: \(dials)")
            return
        }
        // A gap or decorative header can be inert even outside the gauge. If a real
        // drag did not move the target, try another visible safe point, not the same gap.
        let startPoint = startPoints[stationaryAttempts % startPoints.count]
        let neededDistance = frame.isEmpty ? viewport.height * 0.3 :
            (isAboveViewport ? top - frame.minY + 48 : frame.maxY - bottom + 48)
        let distance = min(max(neededDistance, 48), viewport.height * 0.3,
                           isAboveViewport ? viewport.maxY - startPoint.y - 12 : startPoint.y - viewport.minY - 12)
        let endPoint = CGPoint(x: startPoint.x, y: startPoint.y + (isAboveViewport ? distance : -distance))
        print("REVEAL attempt=\(attempt) frame=\(frame) dials=\(dials) start=\(startPoint) end=\(endPoint)")
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: startPoint.x - appFrame.minX, dy: startPoint.y - appFrame.minY))
            .press(forDuration: 0.01, thenDragTo:
                origin.withOffset(CGVector(dx: endPoint.x - appFrame.minX, dy: endPoint.y - appFrame.minY)),
                   withVelocity: .slow, thenHoldForDuration: 0.15)
    }
    XCTAssertTrue(element.exists && !element.frame.isEmpty && viewport.contains(element.frame)
                  && (!requireHittable || element.isHittable),
                  "Expected reachable card control: \(element), frame: \(element.frame), viewport: \(viewport)")
}
