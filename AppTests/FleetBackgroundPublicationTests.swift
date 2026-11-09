import Foundation
import Testing
#if os(iOS)
@preconcurrency import BackgroundTasks
#endif
#if os(macOS)
@testable import HashFleetMac
#else
@testable import HashFleet
#endif

@Suite("Local background snapshot publication") @MainActor
struct FleetBackgroundPublicationTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample(isDemo: Bool = false) -> FleetGlance {
        FleetGlance(updatedAt: date, onlineCount: 1, minerCount: 2,
            hashrateGHs: 1200, powerWatts: 20, isDemo: isDemo)
    }

    @Test(arguments: [false, true])
    func completeReadingPreservesObservationTimeAndDemoIdentity(demo: Bool) async {
        var published: [FleetGlance] = []
        let glance = sample(isDemo: demo)
        let result = await FleetBackgroundGlancePublication.publish(
            glance, isComplete: true, expectedDemo: demo, at: date.addingTimeInterval(2)
        ) { published.append($0) }
        #expect(result)
        #expect(published == [glance])
        #expect(published.first?.updatedAt == date)
    }

    @Test func incompleteEmptyInvalidExpiredAndCrossDemoReadingsNeverPublish() async {
        var calls = 0
        var invalid = sample()
        invalid = FleetGlance(updatedAt: invalid.updatedAt, onlineCount: 1, minerCount: 2,
            hashrateGHs: .nan, powerWatts: 20, isDemo: false)
        for (glance, complete, demo, now) in [
            (sample(), false, false, date),
            (FleetGlance.empty, true, false, date),
            (invalid, true, false, date),
            (sample(), true, false, date.addingTimeInterval(60)),
            (sample(), true, false, date.addingTimeInterval(-6)),
            (sample(isDemo: true), true, false, date),
            (sample(), true, true, date)
        ] {
            let result = await FleetBackgroundGlancePublication.publish(
                glance, isComplete: complete, expectedDemo: demo, at: now
            ) { _ in calls += 1 }
            #expect(!result)
        }
        #expect(calls == 0)
    }

    @Test func cancellationBeforePublicationNeverTouchesTheCache() async {
        var calls = 0
        let work = Task { @MainActor in
            await FleetBackgroundGlancePublication.publish(
                sample(), isComplete: true, expectedDemo: false, at: date
            ) { _ in calls += 1 }
        }
        work.cancel()
        #expect(await work.value == false)
        #expect(calls == 0)
    }

    @Test func cancellationDuringPublisherDoesNotReportSuccessfulCompletion() async {
        let result = await Task { @MainActor in
            await FleetBackgroundGlancePublication.publish(
                sample(), isComplete: true, expectedDemo: false, at: date
            ) { _ in withUnsafeCurrentTask { $0?.cancel() } }
        }.value
        #expect(!result)
    }

    #if os(iOS)
    @Test func completeSnapshotDiagnosticsDoNotAssertCachePersistenceOrWidgetDelivery() async throws {
        let suite = "app.hashfleet.background.persistence.tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "app.hashfleet.shareWithWidgets")
        let unavailableStorage = FleetGlanceStorage(defaults: nil)
        let coordinator = FleetGlanceCoordinator(defaults: defaults, storage: unavailableStorage,
            activityName: "Isolated background publication \(suite)")
        let diagnostics = FleetBackgroundRefreshDiagnostics(defaults: defaults)
        let run = diagnostics.began(at: date)
        let complete = await FleetBackgroundGlancePublication.publish(
            sample(), isComplete: true, expectedDemo: false, at: date
        ) { await coordinator.publish($0) }
        diagnostics.finished(run, outcome: complete ? .completeSnapshot : .noCompleteSnapshot, at: date)

        #expect(complete, "The existing gate certifies a complete snapshot, not the publisher's storage result")
        #expect(coordinator.error?.contains("Could not save the shared widget snapshot") == true)
        #expect(unavailableStorage.load() == .empty)
        #expect(diagnostics.snapshot.outcome == .completeSnapshot)
    }
    #endif
}

@Suite("Private local refresh diagnostics") @MainActor
struct FleetBackgroundRefreshDiagnosticsTests {
    private func fixture() throws -> (String, UserDefaults, FleetBackgroundRefreshDiagnostics) {
        let suite = "app.hashfleet.background.tests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (suite, defaults, FleetBackgroundRefreshDiagnostics(defaults: defaults))
    }

    @Test func requestAcceptanceIsSeparateFromExecutionAndFailureIsVisible() throws {
        let (suite, defaults, diagnostics) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(diagnostics.snapshot.startedAt == nil)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        diagnostics.submitted(.refresh, result: .accepted, at: date)
        diagnostics.submitted(.processing, result: .notPermitted, at: date)
        #expect(diagnostics.snapshot.refresh?.submission == .accepted)
        #expect(diagnostics.snapshot.processing?.submission == .notPermitted)
        #expect(diagnostics.snapshot.startedAt == nil)
        #expect(diagnostics.snapshot.outcome == nil)
        #expect(FleetBackgroundRefreshDiagnostics.Submission.accepted.explanation.contains("iOS chooses"))
        let reloaded = FleetBackgroundRefreshDiagnostics(defaults: defaults)
        #expect(reloaded.snapshot == diagnostics.snapshot)
    }

    @Test func olderRunsAndLateCompletionsCannotOverwriteANewerResult() throws {
        let (suite, defaults, diagnostics) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        let old = diagnostics.began()
        let current = diagnostics.began()
        diagnostics.finished(old, outcome: .completeSnapshot)
        #expect(diagnostics.snapshot.outcome == nil)
        diagnostics.finished(current, outcome: .expired)
        diagnostics.finished(current, outcome: .completeSnapshot)
        #expect(diagnostics.snapshot.outcome == .expired)
        #expect(diagnostics.snapshot.finishedAt != nil)
    }

    @Test func storageRemainsBoundedAndContainsOnlyDiagnosticFields() throws {
        let (suite, defaults, diagnostics) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        for _ in 0..<100 {
            diagnostics.submitted(.refresh, result: .failed)
            let run = diagnostics.began()
            diagnostics.finished(run, outcome: .noCompleteSnapshot)
        }
        let domain = try #require(defaults.persistentDomain(forName: suite))
        #expect(domain.count == 1)
        let data = try #require(domain.values.first as? Data)
        #expect(data.count < 1024)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys).isSubset(of: ["refresh", "processing", "runID", "startedAt", "finishedAt", "outcome"]))
        let key = try #require(domain.keys.first)
        defaults.set(Data("not-json".utf8), forKey: key)
        #expect(diagnostics.snapshot == .init())
    }

    @Test func settingsReadsInjectedDiagnosticsWithoutSystemOrNetworkCalls() async {
        let suite = "app.hashfleet.background.settings.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var state = FleetBackgroundRefreshDiagnostics.Snapshot()
        let model = FleetNotificationSettingsModel(preferences: FleetPreferences(defaults: defaults),
            readAccess: { .init(authorization: .denied) }, requestAccess: { false },
            readBackgroundStatus: { .denied }, readBackgroundDiagnostics: { state },
            postTestNotification: {})
        await model.refresh()
        #expect(model.backgroundDiagnostics.startedAt == nil)
        state.startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        state.outcome = .noCompleteSnapshot
        await model.refresh()
        #expect(model.backgroundDiagnostics == state)
        #expect(model.backgroundTitle.contains("unavailable"))
    }
}

#if os(iOS)
@Suite("Background callback isolation") @MainActor
struct FleetBackgroundCallbackIsolationTests {
    @Test func bothLaunchHandlersExplicitlyChooseTheMainQueue() {
        var identifiers: [String] = []
        FleetBackgroundRefresh.registerHandlers { identifier, queue, _ in
            identifiers.append(identifier)
            #expect(queue === DispatchQueue.main)
            return true
        }
        #expect(identifiers == [
            FleetBackgroundRefresh.widgetIdentifier,
            FleetBackgroundRefresh.fleetIdentifier
        ])
    }

    @Test func expirationCancelsSynchronouslyFromABackgroundQueue() async {
        let work = Task<Void, Never> {
            do { try await Task.sleep(for: .seconds(60)) } catch {}
        }
        // The explicit type also checks that the production callback can cross actors.
        let expire: @Sendable () -> Void = FleetBackgroundRefresh.expirationHandler(
            for: work, runID: UUID()
        )
        let cancelledBeforeReturn = await withCheckedContinuation { continuation in
            DispatchQueue(label: "app.hashfleet.tests.background-expiration").async {
                dispatchPrecondition(condition: .notOnQueue(.main))
                expire()
                continuation.resume(returning: work.isCancelled)
            }
        }
        #expect(cancelledBeforeReturn)
        await work.value
    }
}
#endif
