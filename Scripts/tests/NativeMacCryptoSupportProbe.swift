import AppKit
import ApplicationServices
import Foundation

/// Installed-app-only acceptance check. Never launches or terminates an app or enters checkout.
/// Clipboard contents stay in memory and are restored unless another application changes them.
@main
@MainActor
struct NativeMacCryptoSupportProbe {
    static func main() {
        setbuf(stdout, nil)
        do {
            try validateInstalledApp()
        } catch {
            fputs("Installed-app Support probe failed: \(error)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    static func validateInstalledApp() throws {
        guard CommandLine.arguments.count == 2,
              let pid = Int32(CommandLine.arguments[1]),
              let application = NSRunningApplication(processIdentifier: pid),
              application.bundleURL?.path == "/Applications/Hash Fleet.app",
              application.bundleIdentifier == "app.hashfleet.mac" else {
            throw Failure("Pass the PID of the sole installed native Hash Fleet app")
        }
        guard AXIsProcessTrusted() else { throw Failure("Accessibility permission is required") }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        application.activate()
        let clipboard = NSPasteboard.general
        let savedItems = (clipboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
        var expectedChangeCount: Int?
        defer {
            if let expectedChangeCount, clipboard.changeCount == expectedChangeCount {
                clipboard.clearContents()
                let restored = savedItems.map { contents in
                    let item = NSPasteboardItem()
                    for (type, data) in contents { item.setData(data, forType: type) }
                    return item
                }
                if !restored.isEmpty { clipboard.writeObjects(restored) }
                print("Original clipboard restored")
            }
        }
        for pass in 1...2 {
            let menu = try waitForMenu(app)
            let support = try requireElement(menu) {
                text($0, kAXTitleAttribute) == "Support Hash Fleet…"
            }
            print("Pass \(pass): opening Support from the application menu")
            try press(support)
            for destination in DeveloperSupportCrypto.allCases {
                let prefix = "about.support.crypto.\(destination.rawValue)"
                let address = try waitForElement(app) { text($0, "AXIdentifier") == "\(prefix).address" }
                let addressText = text(address, kAXValueAttribute) + text(address, kAXDescriptionAttribute)
                guard addressText.contains(destination.address) else { throw Failure("Wrong displayed \(destination.rawValue) destination") }
                _ = try waitForElement(app) {
                    text($0, kAXValueAttribute) == destination.network || text($0, kAXDescriptionAttribute) == destination.network
                }
                let button = try waitForElement(app) { text($0, "AXIdentifier") == "\(prefix).copy" }
                guard attribute(button, kAXEnabledAttribute) as? Bool == true else { throw Failure("Copy action disabled") }
                try press(button)
                let deadline = Date.now.addingTimeInterval(5)
                var confirmed = false
                while Date.now < deadline {
                    if clipboard.string(forType: .string) == destination.address {
                        expectedChangeCount = clipboard.changeCount
                        let label = text(button, kAXTitleAttribute) + text(button, kAXDescriptionAttribute)
                        if label.contains("Copied \(destination.rawValue) address") {
                            confirmed = true
                            break
                        }
                    }
                    RunLoop.current.run(until: Date.now.addingTimeInterval(0.1))
                }
                guard confirmed else { throw Failure("Copy or success feedback failed for \(destination.rawValue)") }
                print("Pass \(pass): \(destination.rawValue) full address, mainnet label, exact clipboard copy and success feedback passed")
            }
            // Reopen from another existing Support entry point without launching another process.
            let about = try requireElement(menu) { text($0, kAXTitleAttribute) == "About Hash Fleet" }
            print("Pass \(pass): opening About from the application menu")
            try press(about)
            let aboutLink = try waitForElement(app) { text($0, "AXIdentifier") == "about.support.link" }
            print("Pass \(pass): About is responsive, opening its internal Support link")
            try press(aboutLink)
            _ = try waitForElement(app) { text($0, "AXIdentifier") == "about.support.crypto.BTC.copy" }
            print("Pass \(pass): About-to-Support navigation passed")
        }
        guard !application.isTerminated else { throw Failure("Installed app exited") }
        print("Installed-app crypto support acceptance passed. No wallet or payment action invoked.")
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func text(_ element: AXUIElement, _ name: String) -> String {
        attribute(element, name) as? String ?? ""
    }

    static func find(_ root: AXUIElement, depth: Int = 0, matching: (AXUIElement) -> Bool) -> AXUIElement? {
        guard depth < 40 else { return nil }
        if matching(root) { return root }
        for child in attribute(root, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            if let result = find(child, depth: depth + 1, matching: matching) { return result }
        }
        return nil
    }

    static func requireElement(_ root: AXUIElement, matching: (AXUIElement) -> Bool) throws -> AXUIElement {
        guard let result = find(root, matching: matching) else { throw Failure("Expected accessible control missing") }
        return result
    }

    static func waitForMenu(_ app: AXUIElement) throws -> AXUIElement {
        let deadline = Date.now.addingTimeInterval(8)
        while Date.now < deadline {
            if let menu = attribute(app, kAXMenuBarAttribute) { return menu as! AXUIElement }
            RunLoop.current.run(until: Date.now.addingTimeInterval(0.1))
        }
        throw Failure("Timed out waiting for the application menu")
    }

    static func waitForElement(_ app: AXUIElement, matching: (AXUIElement) -> Bool) throws -> AXUIElement {
        let deadline = Date.now.addingTimeInterval(8)
        while Date.now < deadline {
            for window in attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
                if let result = find(window, matching: matching) { return result }
            }
            RunLoop.current.run(until: Date.now.addingTimeInterval(0.1))
        }
        throw Failure("Timed out waiting for accessible support control")
    }

    static func press(_ element: AXUIElement) throws {
        guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
            throw Failure("Accessible control could not be pressed")
        }
    }
}
