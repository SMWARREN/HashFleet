#!/usr/bin/swift
import AppKit
import ApplicationServices

// Read-only acceptance probe for an explicitly selected, isolated native demo PID.
// Run after opening each page. It catches content that escapes the actual NSWindow,
// including the former 21,221pt Preferences split view and displaced sidebar.
// Usage: swift Scripts/check-native-workspace.swift PID "App settings" [--require-add-target]
//        [--require-visible-control=monitoring.preferences]
//        [--require-page-section=energy.rateSection] [--expect-single-column]
//        [--require-unified-window-controls]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2, let pid = Int32(args[0]), pid > 0 else {
    fail("Expected an isolated demo PID and exact window title")
}
let expectedTitle = args[1]
let ps = Process()
let pipe = Pipe()
ps.executableURL = URL(fileURLWithPath: "/bin/ps")
ps.arguments = ["-p", String(pid), "-o", "command="]
ps.standardOutput = pipe
try ps.run()
let commandData = pipe.fileHandleForReading.readDataToEndOfFile()
ps.waitUntilExit()
let command = String(decoding: commandData, as: UTF8.self)
guard ps.terminationStatus == 0,
      command.contains("Hash Fleet.app/Contents/MacOS/Hash Fleet"),
      command.contains("--ui-testing"), command.contains("--demo") else {
    fail("Refusing to inspect an unverified or non-demo process")
}

guard AXIsProcessTrusted() else { fail("Accessibility permission is required") }
let app = AXUIElementCreateApplication(pid)

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
    return result
}
func string(_ element: AXUIElement, _ name: String) -> String {
    attribute(element, name) as? String ?? ""
}
func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}
func actions(_ element: AXUIElement) -> [String] {
    var result: CFArray?
    guard AXUIElementCopyActionNames(element, &result) == .success else { return [] }
    return result as? [String] ?? []
}
func frame(_ element: AXUIElement) -> CGRect? {
    guard let rawPosition = attribute(element, kAXPositionAttribute),
          let rawSize = attribute(element, kAXSizeAttribute),
          CFGetTypeID(rawPosition) == AXValueGetTypeID(),
          CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(rawPosition as! AXValue, .cgPoint, &point),
          AXValueGetValue(rawSize as! AXValue, .cgSize, &size) else { return nil }
    return CGRect(origin: point, size: size)
}
func describe(_ element: AXUIElement) -> [String: Any] {
    let rect = frame(element) ?? .zero
    return [
        "role": string(element, kAXRoleAttribute),
        "title": string(element, kAXTitleAttribute),
        "description": string(element, kAXDescriptionAttribute),
        "identifier": string(element, "AXIdentifier"),
        "frame": [rect.minX, rect.minY, rect.width, rect.height]
    ]
}

let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
let workspaces = windows.filter {
    !string($0, kAXTitleAttribute).isEmpty && (frame($0)?.height ?? 0) > 100
}
guard workspaces.count == 1, let window = workspaces.first, let windowFrame = frame(window) else {
    fail("Expected exactly one titled workspace, observed \(workspaces.count) among \(windows.count) AX windows")
}
guard string(window, kAXTitleAttribute) == expectedTitle else {
    fail("Expected window title \(expectedTitle), observed \(string(window, kAXTitleAttribute))")
}
let isFullscreen = attribute(window, "AXFullScreen") as? Bool == true
let toolbarCompanions = windows.filter { !CFEqual($0, window) }
// AppKit exposes its fullscreen menu/toolbar strip as a second untitled AXWindow.
// Accept only that physically adjoining strip, never another workspace or dialog.
for companion in toolbarCompanions {
    guard isFullscreen, string(companion, kAXTitleAttribute).isEmpty,
          let rect = frame(companion), rect.height > 0, rect.height <= 100,
          abs(rect.minX - windowFrame.minX) < 2,
          abs(rect.width - windowFrame.width) < 2,
          abs(rect.maxY - windowFrame.minY) < 2 else {
        fail("Unexpected additional AX window, not an adjoining fullscreen toolbar companion")
    }
}

var elements: [AXUIElement] = []
var queue = children(window)
var cursor = 0
while cursor < queue.count && cursor < 4_000 {
    let element = queue[cursor]
    cursor += 1
    elements.append(element)
    queue.append(contentsOf: children(element))
}
guard cursor < 4_000 else { fail("Accessibility tree exceeded the bounded inspection budget") }

let splits = elements.filter { string($0, kAXRoleAttribute) == kAXSplitGroupRole }
guard !splits.isEmpty else { fail("Workspace split view is missing") }
let toleratedWindow = windowFrame.insetBy(dx: -2, dy: -2)
var errors: [String] = []
var windowControls: [[String: Any]] = []
if args.contains("--require-unified-window-controls") {
    let toolbar = elements.first { string($0, kAXRoleAttribute) == kAXToolbarRole }
    let toolbarFrame = toolbar.flatMap(frame)
    for key in [kAXCloseButtonAttribute, kAXMinimizeButtonAttribute, kAXZoomButtonAttribute] {
        guard let rawControl = attribute(window, key), CFGetTypeID(rawControl) == AXUIElementGetTypeID() else {
            errors.append("Native window control is missing: \(key)")
            continue
        }
        let control = rawControl as! AXUIElement
        windowControls.append(describe(control))
        guard let rect = frame(control), rect.width > 0, rect.height > 0,
              let toolbarFrame, toolbarFrame.insetBy(dx: -2, dy: -2).contains(rect) else {
            errors.append("Native window control is outside the unified toolbar: \(key)")
            continue
        }
        if !toleratedWindow.contains(rect) {
            errors.append("Native window control is outside the window: \(key)")
        }
    }
}
for split in splits {
    guard let rect = frame(split), rect.width > 0, rect.height > 0 else {
        errors.append("Split view has no usable frame")
        continue
    }
    if !toleratedWindow.contains(rect) {
        errors.append("Split view escapes window: \(rect), window: \(windowFrame)")
    }
}

let sidebar = elements.first {
    string($0, kAXRoleAttribute) == kAXOutlineRole && string($0, kAXDescriptionAttribute) == "Sidebar"
}
if let sidebar, let rect = frame(sidebar) {
    if !toleratedWindow.contains(rect) { errors.append("Sidebar escapes window: \(rect)") }
} else {
    errors.append("Visible sidebar is missing")
}

let addMatches = elements.filter { string($0, "AXIdentifier") == "sidebar.addMiner" }
let add = addMatches.first { string($0, kAXRoleAttribute) == kAXButtonRole }
if args.contains("--require-add-target") {
    if let add, let rect = frame(add) {
        if rect.width < 44 || rect.height < 44 { errors.append("Add target is smaller than 44pt: \(rect)") }
        if !toleratedWindow.contains(rect) { errors.append("Add target is outside the window: \(rect)") }
    } else {
        errors.append("Sidebar Add target is missing")
    }
}

let requiredControlIDs = args.dropFirst(2).compactMap { argument -> String? in
    let prefix = "--require-visible-control="
    guard argument.hasPrefix(prefix) else { return nil }
    return String(argument.dropFirst(prefix.count))
}
var requiredControls: [[String: Any]] = []
for id in requiredControlIDs {
    let matches = elements.filter {
        string($0, "AXIdentifier") == id &&
            !Set(actions($0)).isDisjoint(with: [kAXPressAction, kAXShowMenuAction])
    }
    guard let control = matches.first(where: { element in
        guard let rect = frame(element), rect.width > 0, rect.height > 0 else { return false }
        return toleratedWindow.contains(rect) && (attribute(element, kAXEnabledAttribute) as? Bool != false)
    }) else {
        errors.append("Required page control is missing, disabled, or outside the window: \(id)")
        continue
    }
    if let sidebar, let sidebarFrame = frame(sidebar), let controlFrame = frame(control),
       sidebarFrame.intersects(controlFrame), !id.hasPrefix("sidebar.") {
        errors.append("Required page control overlaps the sidebar: \(id)")
    }
    requiredControls.append(describe(control))
}

// Inspect the real section groups, not the backing ScrollView/List frame. Native
// List accessibility can report the full window even when its visible rows overlap
// the sidebar. Section groups retain all their individual interactive children.
let requiredSectionIDs = args.dropFirst(2).compactMap { argument -> String? in
    let prefix = "--require-page-section="
    guard argument.hasPrefix(prefix) else { return nil }
    return String(argument.dropFirst(prefix.count))
}
var requiredSections: [[String: Any]] = []
if !requiredSectionIDs.isEmpty {
    if let sidebar, let sidebarFrame = frame(sidebar) {
        let gutter: CGFloat = 16
        let left = sidebarFrame.maxX + gutter
        // macOS can reserve a permanent scroller lane, depending on the user's
        // system preference. The common shell pads the scroll content viewport,
        // not the scroller itself. Measure that actual edge rather than treating
        // a reserved scrollbar as extra page padding.
        let detailScrollerEdge = elements.filter {
            NSScroller.preferredScrollerStyle == .legacy
                && string($0, kAXRoleAttribute) == kAXScrollBarRole
        }.compactMap(frame).filter {
            $0.height > $0.width && $0.width > 0 && $0.minX > sidebarFrame.maxX
                && $0.maxX >= windowFrame.maxX - 2
        }.map(\.minX).min() ?? windowFrame.maxX
        let right = min(windowFrame.maxX, detailScrollerEdge) - gutter
        var sectionFrames: [CGRect] = []
        for id in requiredSectionIDs {
            let matches = elements.filter {
                string($0, "AXIdentifier") == id && string($0, kAXRoleAttribute) == kAXGroupRole
            }
            guard matches.count == 1, let section = matches.first, let rect = frame(section),
                  rect.width > 0, rect.height > 0 else {
                errors.append("Expected one measurable section group: \(id), found \(matches.count)")
                continue
            }
            if rect.minX < left - 2 || rect.maxX > right + 2 {
                errors.append("Section escapes the common page gutters: \(id), frame: \(rect), expected x \(left)...\(right)")
            }
            if args.contains("--expect-single-column"),
               abs(rect.minX - left) > 2 || abs(rect.maxX - right) > 2 {
                errors.append("Single-column section does not fill the common page shell: \(id), frame: \(rect)")
            }
            sectionFrames.append(rect)
            requiredSections.append(describe(section))
        }
        if let firstEdge = sectionFrames.map(\.minX).min(),
           let lastEdge = sectionFrames.map(\.maxX).max(),
           abs(firstEdge - left) > 2 || abs(lastEdge - right) > 2 {
            errors.append("Page sections do not use both common 16pt outer gutters")
        }
    } else {
        errors.append("Cannot measure page gutters without a sidebar")
    }
}

var report: [String: Any] = [
    "pid": pid,
    "expectedTitle": expectedTitle,
    "window": describe(window),
    "fullscreen": isFullscreen,
    "toolbarCompanions": toolbarCompanions.map(describe),
    "splitViews": splits.map(describe),
    "pageControls": elements.filter {
        let id = string($0, "AXIdentifier")
        return id.hasPrefix("monitoring.") || id.hasPrefix("preferences.")
    }.map(describe),
    "addIdentifierMatches": addMatches.map(describe),
    "requiredControls": requiredControls,
    "requiredSections": requiredSections,
    "windowControls": windowControls,
    "passed": errors.isEmpty,
    "errors": errors
]
if let sidebar { report["sidebar"] = describe(sidebar) }
if let add { report["addTarget"] = describe(add) }
let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
if !errors.isEmpty { exit(1) }
