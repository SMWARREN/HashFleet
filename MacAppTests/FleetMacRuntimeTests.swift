import AppKit
import Foundation
import Testing
@testable import HashFleetMac

@Suite("Native Mac single-process lifecycle", .serialized)
struct FleetMacRuntimeTests {
    @MainActor
    private func isolatedRuntime() -> (FleetMacRuntime, String) {
        let suite = "app.hashfleet.mac.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let runtime = FleetMacRuntime(defaults: defaults, isTesting: true)
        runtime.store.loadDemo()
        return (runtime, suite)
    }

    @MainActor
    @Test func applicationOwnsOneRuntimeAcrossRepeatedStartsAndStops() async throws {
        let (runtime, suite) = isolatedRuntime()
        defer {
            runtime.stop()
            runtime.defaults.removePersistentDomain(forName: suite)
        }
        let store = runtime.store
        #expect(!runtime.isRunning)
        #expect(runtime.isTesting)
        runtime.start()
        runtime.start()
        try await Task.sleep(for: .milliseconds(30))
        #expect(runtime.isRunning)
        #expect(runtime.store === store)
        #expect(runtime.store.isDemo)
        #expect(runtime.store.liveTasks.isEmpty)
        runtime.stop()
        runtime.stop()
        #expect(!runtime.isRunning)
        #expect(runtime.store.liveTasks.isEmpty)
        runtime.start()
        #expect(runtime.isRunning)
        #expect(runtime.store === store)
    }

    @MainActor
    @Test func closingWorkspaceDoesNotQuitAndReopenUsesTheSameWindow() {
        let delegate = FleetMacAppDelegate()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 660),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        delegate.mainWindow = window
        defer { window.close() }
        #expect(!delegate.applicationShouldTerminateAfterLastWindowClosed(.shared))
        delegate.showMainWindow()
        #expect(window.isVisible)
        window.close()
        #expect(!window.isVisible)
        #expect(delegate.applicationShouldHandleReopen(.shared, hasVisibleWindows: false))
        #expect(window.isVisible)
        #expect(delegate.mainWindow === window)
    }

    @MainActor
    @Test func reopenRequestsTheSwiftUISceneEvenWithACachedClosedWindow() {
        let delegate = FleetMacAppDelegate()
        let retiredWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 660),
                                     styleMask: [.titled, .closable], backing: .buffered, defer: false)
        retiredWindow.isReleasedWhenClosed = false
        retiredWindow.close()
        delegate.mainWindow = retiredWindow
        var sceneOpenCount = 0
        delegate.openWorkspace = { sceneOpenCount += 1 }

        delegate.showMainWindow()
        #expect(sceneOpenCount == 1)
        #expect(!retiredWindow.isVisible)
        #expect(delegate.applicationShouldHandleReopen(.shared, hasVisibleWindows: false))
        #expect(sceneOpenCount == 2)
        #expect(!retiredWindow.isVisible)
    }

    @MainActor
    @Test func nativeGlanceDoesNotEnableMobileWidgetsOrActivities() async {
        let (runtime, suite) = isolatedRuntime()
        defer { runtime.defaults.removePersistentDomain(forName: suite) }
        let glance = runtime.glanceCoordinator
        #expect(!glance.sharesWithWidgets)
        #expect(!glance.widgetStorageAvailable)
        #expect(!glance.activitiesAllowed)
        await glance.start(runtime.store.glance)
        #expect(!glance.hasLiveActivity)
        #expect(glance.error?.contains("not on macOS") == true)
    }
}
