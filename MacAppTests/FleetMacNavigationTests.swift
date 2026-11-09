import AppKit
import SwiftUI
import Testing
@testable import HashFleetMac

@Suite("Native command and sidebar navigation")
struct FleetMacNavigationTests {
    @MainActor
    @Test func commandsAndSidebarShareOneNavigationReference() {
        let navigation = FleetMacNavigationState()
        let sidebar = Binding(
            get: { navigation.sidebarSelection },
            set: { navigation.sidebarSelection = $0 }
        )

        for destination in [FleetSidebarDestination.reports, .network, .energy, .achievements, .overview] {
            navigation.fleetPath.append("previous detail")
            navigation.select(destination)
            #expect(sidebar.wrappedValue == destination)
            #expect(navigation.fleetPath.isEmpty)
        }

        sidebar.wrappedValue = .preferences
        #expect(navigation.sidebarSelection == .preferences)
        navigation.select(.overview)
        #expect(sidebar.wrappedValue == .overview)
    }
}

// In-process hosted graph regression for native guided-preview boundaries. This is not UI
// automation or workflow acceptance. No NSWindow is constructed, ordered, or attached.
// The matching normal-navigation controls must render destinations, or the fixture fails.
private enum FleetPageHostedKind: String, CaseIterable, Sendable {
    case boolean
    case item
}

private struct FleetPageHostedPayload: Identifiable, Equatable, Sendable {
    let id: Int
}

@MainActor
private final class FleetPageHostedRecorder {
    // Non-observable counters avoid invalidating the graph under test.
    var booleanValue = true
    var itemValue: FleetPageHostedPayload? = FleetPageHostedPayload(id: 7)
    var bindingWrites = 0
    var dismissals = 0
    var rootBodyEvaluations = 0
    var baseBodyEvaluations = 0
    var destinationBuilds = 0
    var destinationBodyEvaluations = 0
    var decoratorInvocations = 0
    var baseGuidedFlags: Set<Bool> = []
    var destinationPayloadIDs: [Int] = []
    var destinationFillsWindow: Set<Bool> = []
    var destinationStandaloneFlags: Set<Bool> = []
    var decoratedBodyEvaluations = 0

    var booleanBinding: Binding<Bool> {
        Binding(get: { self.booleanValue }, set: {
            self.bindingWrites += 1
            self.booleanValue = $0
        })
    }

    var itemBinding: Binding<FleetPageHostedPayload?> {
        Binding(get: { self.itemValue }, set: {
            self.bindingWrites += 1
            self.itemValue = $0
        })
    }

    func destination(payload: FleetPageHostedPayload? = nil) -> FleetPageHostedDestination {
        destinationBuilds += 1
        if let payload { destinationPayloadIDs.append(payload.id) }
        return FleetPageHostedDestination(recorder: self)
    }
}

@MainActor
private struct FleetPageHostedBase: View {
    let recorder: FleetPageHostedRecorder
    let revision: Int
    @Environment(\.fleetGuidedDemo) private var guidedDemo

    var body: some View {
        recorder.baseBodyEvaluations += 1
        recorder.baseGuidedFlags.insert(guidedDemo)
        return Text("Hosted base \(revision)").frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
private struct FleetPageHostedDestination: View {
    let recorder: FleetPageHostedRecorder
    @Environment(\.fleetFullWindowPresentation) private var fillsWindow
    @Environment(\.fleetStandalonePage) private var standalonePage

    var body: some View {
        recorder.destinationBodyEvaluations += 1
        recorder.destinationFillsWindow.insert(fillsWindow)
        recorder.destinationStandaloneFlags.insert(standalonePage)
        return Text("Hosted destination").frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
private struct FleetPageHostedRoot: View {
    let recorder: FleetPageHostedRecorder
    let kind: FleetPageHostedKind
    let guidedDemo: Bool
    let revision: Int

    var body: some View {
        recorder.rootBodyEvaluations += 1
        return NavigationStack {
            page.environment(\.fleetGuidedDemo, guidedDemo)
        }
        .frame(width: 640, height: 480)
    }

    @ViewBuilder private var page: some View {
        switch kind {
        case .boolean:
            FleetPageHostedBase(recorder: recorder, revision: revision)
                .fleetPagePresentation(isPresented: recorder.booleanBinding,
                    onDismiss: { recorder.dismissals += 1 }, content: { recorder.destination() })
        case .item:
            FleetPageHostedBase(recorder: recorder, revision: revision)
                .fleetPagePresentation(item: recorder.itemBinding,
                    onDismiss: { recorder.dismissals += 1 }, content: { recorder.destination(payload: $0) })
        }
    }
}

@MainActor
private struct FleetDecoratorHostedRoot: View {
    let recorder: FleetPageHostedRecorder
    let guidedDemo: Bool

    var body: some View {
        recorder.rootBodyEvaluations += 1
        return NavigationStack {
            FleetPageHostedBase(recorder: recorder, revision: 1)
                .fleetAppNavigation { base in
                    recorder.decoratorInvocations += 1
                    return base.navigationTitle("Hosted raw registration")
                        .background(FleetDecoratorBodyProbe(recorder: recorder))
                }
                .environment(\.fleetGuidedDemo, guidedDemo)
        }
        .frame(width: 640, height: 480)
    }
}

@MainActor
private struct FleetDecoratorBodyProbe: View {
    let recorder: FleetPageHostedRecorder
    var body: some View {
        recorder.decoratedBodyEvaluations += 1
        return Color.clear
    }
}

@Suite("Native guided-preview hosted presentation boundary", .serialized)
struct FleetGuidedPresentationHostedTests {
    @MainActor @Test func guidedBooleanPresentationIsInertWithRenderedNormalControl() async throws {
        try await verifyGuidedBoundary(kind: .boolean)
    }

    @MainActor @Test func guidedItemPresentationIsInertWithRenderedNormalControl() async throws {
        try await verifyGuidedBoundary(kind: .item)
    }

    @MainActor @Test func nativeNavigationDecoratorHasRenderedPositiveControl() async throws {
        let guided = FleetPageHostedRecorder()
        let guidedHost = makeDecoratorHost(recorder: guided, guidedDemo: true)
        try await exerciseDecorator(guidedHost, recorder: guided, guidedDemo: true)
        #expect(guided.rootBodyEvaluations > 0)
        #expect(guided.baseBodyEvaluations > 0)
        #expect(guided.baseGuidedFlags == Set([true]))
        #expect(guided.decoratorInvocations == 0)
        #expect(guided.decoratedBodyEvaluations == 0)

        let normal = FleetPageHostedRecorder()
        let normalHost = makeDecoratorHost(recorder: normal, guidedDemo: false)
        try await exerciseDecorator(normalHost, recorder: normal, guidedDemo: false)
        try #require(normal.decoratorInvocations > 0, "Normal control must invoke the raw decorator")
        try #require(normal.decoratedBodyEvaluations > 0, "Normal control must render decorated content")
        #expect(normal.baseBodyEvaluations > 0)
        #expect(normal.baseGuidedFlags == Set([false]))
        #expect(normalHost.window == nil)
        #expect(guidedHost.window == nil)
        #expect(guided.rootBodyEvaluations > 0)
        #expect(guided.baseBodyEvaluations > 0)
        #expect(guided.baseGuidedFlags == Set([true]))
        #expect(guided.decoratorInvocations == 0)
        #expect(guided.decoratedBodyEvaluations == 0)
        withExtendedLifetime((guidedHost, normalHost)) {}
    }

    @MainActor private func verifyGuidedBoundary(kind: FleetPageHostedKind) async throws {
        let guided = FleetPageHostedRecorder()
        let guidedHost = makeHost(recorder: guided, kind: kind, guidedDemo: true)
        try await exercise(guidedHost, recorder: guided, kind: kind, guidedDemo: true)
        try #require(guided.rootBodyEvaluations > 0, "Hosted root must execute")
        try #require(guided.baseBodyEvaluations > 0, "Base content must render")
        #expect(guided.baseGuidedFlags == Set([true]), "Base inherits guided environment")
        #expect(guided.destinationBuilds == 0)
        #expect(guided.destinationBodyEvaluations == 0)
        #expect(guided.bindingWrites == 0)
        #expect(guided.dismissals == 0)
        #expect(guided.booleanValue)
        #expect(guided.itemValue == FleetPageHostedPayload(id: 7))
        #expect(guided.destinationPayloadIDs.isEmpty)
        #expect(guidedHost.window == nil)

        // Identical fixture and initially active presentation, with only the flag changed.
        let normal = FleetPageHostedRecorder()
        let normalHost = makeHost(recorder: normal, kind: kind, guidedDemo: false)
        try await exercise(normalHost, recorder: normal, kind: kind, guidedDemo: false)
        try #require(normal.destinationBuilds > 0, "Normal navigation must build destination")
        try #require(normal.destinationBodyEvaluations > 0, "Normal destination must actually render")
        #expect(normal.destinationFillsWindow == Set([true]))
        #expect(normal.destinationStandaloneFlags == Set([false]))
        if kind == .item {
            #expect(!normal.destinationPayloadIDs.isEmpty)
            #expect(normal.destinationPayloadIDs.allSatisfy { $0 == 7 })
        }
        #expect(normalHost.window == nil)

        // Catch callbacks deferred while the normal positive control was processing.
        #expect(guided.destinationBuilds == 0)
        #expect(guided.destinationBodyEvaluations == 0)
        #expect(guided.bindingWrites == 0)
        #expect(guided.dismissals == 0)
        #expect(guided.booleanValue)
        #expect(guided.itemValue == FleetPageHostedPayload(id: 7))
        #expect(guidedHost.window == nil)
        withExtendedLifetime((guidedHost, normalHost)) {}
    }

    @MainActor private func makeHost(recorder: FleetPageHostedRecorder, kind: FleetPageHostedKind,
                                     guidedDemo: Bool) -> NSHostingView<FleetPageHostedRoot> {
        let host = NSHostingView(rootView: FleetPageHostedRoot(recorder: recorder, kind: kind,
            guidedDemo: guidedDemo, revision: 0))
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        return host
    }

    @MainActor private func makeDecoratorHost(recorder: FleetPageHostedRecorder,
                                              guidedDemo: Bool) -> NSHostingView<FleetDecoratorHostedRoot> {
        let host = NSHostingView(rootView: FleetDecoratorHostedRoot(recorder: recorder, guidedDemo: guidedDemo))
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        return host
    }

    @MainActor private func exercise(_ host: NSHostingView<FleetPageHostedRoot>,
                                     recorder: FleetPageHostedRecorder, kind: FleetPageHostedKind,
                                     guidedDemo: Bool) async throws {
        for revision in 1...40 {
            try Task.checkCancellation()
            host.rootView = FleetPageHostedRoot(recorder: recorder, kind: kind,
                guidedDemo: guidedDemo, revision: revision)
            host.needsLayout = true
            host.layoutSubtreeIfNeeded()
            _ = host.fittingSize
            try await Task.sleep(for: .milliseconds(10))
            host.layoutSubtreeIfNeeded()
        }
        try #require(host.window == nil, "Fixture must remain unshown")
    }

    @MainActor private func exerciseDecorator(_ host: NSHostingView<FleetDecoratorHostedRoot>,
                                              recorder: FleetPageHostedRecorder,
                                              guidedDemo: Bool) async throws {
        for _ in 1...40 {
            try Task.checkCancellation()
            host.rootView = FleetDecoratorHostedRoot(recorder: recorder, guidedDemo: guidedDemo)
            host.needsLayout = true
            host.layoutSubtreeIfNeeded()
            _ = host.fittingSize
            try await Task.sleep(for: .milliseconds(10))
            host.layoutSubtreeIfNeeded()
        }
        try #require(host.window == nil, "Fixture must remain unshown")
    }
}
