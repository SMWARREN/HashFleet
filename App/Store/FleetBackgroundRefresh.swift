@preconcurrency import BackgroundTasks
import Foundation
import HashFleetCore

/// Schedules local, best-effort refreshes for widget data and all configured alert detectors.
@MainActor
enum FleetBackgroundRefresh {
    static let widgetIdentifier = "app.hashfleet.widget-refresh"
    static let fleetIdentifier = "app.hashfleet.fleet-refresh"
    private static var registered = false
    private static let refreshInterval: TimeInterval = 2 * 60 // 2 minutes
    private static let processingInterval: TimeInterval = 5 * 60 // 5 minutes

    static func register() {
        guard !registered else { return }
        registered = true

        registerHandlers(using: BGTaskScheduler.shared.register(forTaskWithIdentifier:using:launchHandler:))
    }

    /// Keep the actual registration arguments observable without registering twice in tests.
    static func registerHandlers(
        using register: (String, DispatchQueue?, @escaping (BGTask) -> Void) -> Bool
    ) {
        // These Objective-C callbacks inherit MainActor isolation. With nil, the SDK
        // invokes them on a background queue and Swift traps before an inner Task can hop.
        _ = register(widgetIdentifier, .main) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            run(refreshTask)
        }

        _ = register(fleetIdentifier, .main) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            run(processingTask)
        }
    }

    static func schedule() {
        guard registered else { return }

        // This is only an earliest start, not a two-minute polling guarantee.
        let refreshRequest = BGAppRefreshTaskRequest(identifier: widgetIdentifier)
        refreshRequest.earliestBeginDate = Date().addingTimeInterval(refreshInterval)
        do {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: widgetIdentifier)
            try BGTaskScheduler.shared.submit(refreshRequest)
            FleetBackgroundRefreshDiagnostics.shared.submitted(.refresh, result: .accepted)
        } catch {
            FleetBackgroundRefreshDiagnostics.shared.submitted(.refresh, result: submissionResult(error))
        }

        // Schedule processing task
        let processingRequest = BGProcessingTaskRequest(identifier: fleetIdentifier)
        processingRequest.earliestBeginDate = Date().addingTimeInterval(processingInterval)
        processingRequest.requiresNetworkConnectivity = true
        do {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: fleetIdentifier)
            try BGTaskScheduler.shared.submit(processingRequest)
            FleetBackgroundRefreshDiagnostics.shared.submitted(.processing, result: .accepted)
        } catch {
            FleetBackgroundRefreshDiagnostics.shared.submitted(.processing, result: submissionResult(error))
        }
    }

    private static func submissionResult(_ error: Error) -> FleetBackgroundRefreshDiagnostics.Submission {
        guard let error = error as? BGTaskScheduler.Error else { return .failed }
        switch error.code {
        case .unavailable: return .unavailable
        case .notPermitted: return .notPermitted
        case .tooManyPendingTaskRequests: return .tooManyRequests
        default: return .failed
        }
    }

    private static func run(_ task: BGTask) {
        schedule()
        let runID = FleetBackgroundRefreshDiagnostics.shared.began()
        let work = Task { @MainActor in
            let coordinator = FleetGlanceCoordinator()
            let store = FleetStore()
            let expectedDemo = store.isDemo
            await store.refresh()
            guard !Task.isCancelled else {
                FleetBackgroundRefreshDiagnostics.shared.finished(runID, outcome: .cancelled)
                task.setTaskCompleted(success: false)
                return
            }

            let complete = await FleetBackgroundGlancePublication.publish(
                store.glance, isComplete: store.canPublishGlance, expectedDemo: expectedDemo
            ) { glance in
                await coordinator.publish(glance)
            }
            guard !Task.isCancelled else {
                FleetBackgroundRefreshDiagnostics.shared.finished(runID, outcome: .cancelled)
                task.setTaskCompleted(success: false)
                return
            }
            FleetNotificationDelivery.replayUndeliveredSystemNotifications(from: store)
            FleetNotificationDelivery.consume(from: store, isActive: false)
            await MinerTelemetryDatabase.shared.flushReadings()
            FleetBackgroundRefreshDiagnostics.shared.finished(runID,
                outcome: Task.isCancelled ? .cancelled : (complete ? .completeSnapshot : .noCompleteSnapshot))
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = expirationHandler(for: work, runID: runID)
    }

    /// Expiration is an Objective-C callback too. Only cancellation is synchronous;
    /// diagnostics explicitly hop to MainActor regardless of the caller's queue.
    nonisolated static func expirationHandler(
        for work: Task<Void, Never>, runID: UUID
    ) -> @Sendable () -> Void {
        { @Sendable in
            work.cancel()
            Task { @MainActor in
                FleetBackgroundRefreshDiagnostics.shared.finished(runID, outcome: .expired)
            }
        }
    }
}
