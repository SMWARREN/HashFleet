import AppKit
import ApplicationServices
import Foundation

// Out-of-process accessibility probe. The Python driver bounds each call so a frozen
// app is a test failure, not a hung XCTest runner. Only the driver's demo PID is used.
let arguments = CommandLine.arguments
if arguments.count == 3, (arguments[1] == "launch" || arguments[1] == "launch-tour") {
    let configuration = NSWorkspace.OpenConfiguration()
    if arguments[1] == "launch-tour" {
        configuration.arguments = ["--ui-testing", "--show-feature-tour"]
    } else {
        configuration.arguments = ["--ui-testing", "--demo"]
    }
    configuration.createsNewApplicationInstance = true
    configuration.activates = false
    NSWorkspace.shared.openApplication(
        at: URL(fileURLWithPath: arguments[2]), configuration: configuration
    ) { application, error in
        guard let application else {
            fputs("Launch failed: \(String(describing: error))\n", stderr)
            exit(1)
        }
        print(application.processIdentifier)
        exit(0)
    }
    RunLoop.main.run()
    exit(1)
}
guard arguments.count >= 3, let pid = Int32(arguments[1]) else {
    fputs("Usage: probe launch APP | probe launch-tour APP | PID list | PID press ID | PID menu TITLE | PID segment TITLE\n", stderr)
    exit(2)
}
let mode = arguments[2]
let target = arguments.count > 3 ? arguments[3] : ""
let app = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(app, 1)
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}
func text(_ element: AXUIElement, _ name: String) -> String {
    attribute(element, name) as? String ?? ""
}
var nodes: [[String: Any]] = []
var visited = 0
func walk(_ element: AXUIElement, depth: Int = 0) {
    guard depth < 40, visited < 6000 else { return }
    visited += 1
    let identifier = text(element, "AXIdentifier")
    let title = text(element, kAXTitleAttribute)
    let role = text(element, kAXRoleAttribute)
    let description = text(element, kAXDescriptionAttribute)
    let isSegment = mode == "segment" && role == kAXRadioButtonRole
        && (title == target || description == target)
    if (mode == "press" && identifier == target) || (mode == "menu" && title == target) || isSegment {
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        print("AXPress \(target): \(result.rawValue)")
        exit(result == .success ? 0 : 1)
    }
    if !identifier.isEmpty || role == kAXWindowRole || role == kAXRadioButtonRole || role == kAXStaticTextRole {
        var nodeInfo: [String: Any] = [
            "id": identifier, "role": role, "title": title,
            "description": description,
            "value": text(element, kAXValueAttribute),
            "enabled": attribute(element, kAXEnabledAttribute) as? Bool ?? false
        ]
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
           AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
           let posVal = posValue, let sizeVal = sizeValue,
           CFGetTypeID(posVal) == AXValueGetTypeID(),
           CFGetTypeID(sizeVal) == AXValueGetTypeID() {
            var point = CGPoint.zero
            var size = CGSize.zero
            let posAX = posVal as! AXValue
            let sizeAX = sizeVal as! AXValue
            if AXValueGetValue(posAX, .cgPoint, &point) && AXValueGetValue(sizeAX, .cgSize, &size) {
                if point.x.isFinite && point.y.isFinite && size.width.isFinite && size.height.isFinite {
                    nodeInfo["frame"] = [
                        "x": Double(point.x),
                        "y": Double(point.y),
                        "width": Double(size.width),
                        "height": Double(size.height)
                    ]
                    nodeInfo["frame_status"] = "valid"
                } else {
                    nodeInfo["frame"] = NSNull()
                    nodeInfo["frame_status"] = "nonfinite"
                }
            } else {
                nodeInfo["frame"] = NSNull()
                nodeInfo["frame_status"] = "unreadable"
            }
        }
        nodes.append(nodeInfo)
    }
    if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
        for child in children { walk(child, depth: depth + 1) }
    }
}
if mode == "menu", let menu = attribute(app, kAXMenuBarAttribute) {
    walk(menu as! AXUIElement)
} else {
    if let extras = attribute(app, "AXExtrasMenuBar") { walk(extras as! AXUIElement) }
    if let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] {
        for window in windows { walk(window) }
    }
}
guard mode == "list" else {
    fputs("Control not found: \(target)\n", stderr)
    exit(2)
}
let data = try JSONSerialization.data(withJSONObject: nodes, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
