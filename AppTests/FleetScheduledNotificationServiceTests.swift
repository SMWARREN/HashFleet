import Foundation
import UserNotifications
import Testing
import HashFleetCore
@testable import HashFleetNotificationTestSupport

@Suite(.timeLimit(.minutes(1)))
struct FleetScheduledNotificationServiceTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let target = FleetScheduledCheckTarget(id: UUID(), name: "Workshop", baseURL: URL(string: "http://192.168.1.10")!, expectedMAC: "02:11:22:33:44:55")

    private func request(valid: Bool = true) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Scheduled miner check"
        content.body = "Open Hash Fleet on your miners' network to check current readings."
        content.userInfo = valid ? ["app.hashfleet.deviceID": target.id.uuidString.lowercased(),
            "app.hashfleet.checkVersion": 1, "app.hashfleet.checkIssuedAt": now.timeIntervalSince1970,
            "app.hashfleet.checkRequestID": UUID().uuidString.lowercased()] : ["invalid": true]
        return UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    }

    @Test func completionIsExactlyOnceAcrossConcurrentSuccessAndExpiry() async {
        let probe = NotificationDeliveryProbe()
        let operation = ScheduledNotificationOperation(content: request().content, handler: { probe.record($0) })
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask {
                    operation.finish(index.isMultiple(of: 2) ? .unavailable : .init(title: "Workshop", body: "Just checked: 2.00 TH/s"))
                }
            }
        }
        #expect(probe.count == 1)
        #expect(probe.categories == ["app.hashfleet.summary"])
    }

    @Test func lateTaskInstallationAfterCompletionIsCancelled() async {
        let probe = NotificationDeliveryProbe()
        let operation = ScheduledNotificationOperation(content: request().content, handler: { probe.record($0) })
        operation.finish(.unavailable)
        let cancelled = CancellationProbe()
        let task = Task {
            do { try await Task.sleep(for: .seconds(60)) } catch {}
            cancelled.set(Task.isCancelled)
        }
        operation.install(task)
        await task.value
        operation.finish(.init(title: "Wrong", body: "Must not replace delivered fallback"))
        #expect(cancelled.value)
        #expect(probe.count == 1)
        #expect(probe.titles == [FleetScheduledCheckPresentation.unavailable.title])
    }

    @Test func malformedPayloadAndDisabledConfigurationNeverReadLAN() async {
        let fixedNow = now
        let service = NotificationService(configuration: { .disabled }, now: { fixedNow }, read: { _ in
            Issue.record("Disabled or malformed request attempted a LAN read")
            return .init(hashRateGHs: 2000)
        })
        for valid in [false, true] {
            let probe = NotificationDeliveryProbe()
            service.didReceive(request(valid: valid), withContentHandler: { probe.record($0) })
            let result = await probe.first()
            #expect(result == .unavailable)
            service.serviceExtensionTimeWillExpire()
            #expect(probe.count == 1)
        }
    }

    @Test func successfulCheckUsesOnlyLocalTargetAndExistingSummaryCategory() async {
        let config = FleetScheduledCheckConfiguration(enabled: true, targets: [target])
        let expected = target
        let fixedNow = now
        let probe = NotificationDeliveryProbe()
        let service = NotificationService(configuration: { config }, now: { fixedNow }, read: { selected in
            #expect(selected == expected)
            return .init(hashRateGHs: 2500, temperatureC: 52, powerW: 40)
        })
        service.didReceive(request(), withContentHandler: { probe.record($0) })
        let result = await probe.first()
        #expect(result.title == "Workshop")
        #expect(result.body == "Just checked: 2.50 TH/s · 52.0 °C · 40.0 W")
        #expect(probe.categories == ["app.hashfleet.summary"])
        service.serviceExtensionTimeWillExpire()
        #expect(probe.count == 1)
    }

    @Test func transportFailureCompletesWithUnavailableNotOfflineOrBlockClaim() async {
        let config = FleetScheduledCheckConfiguration(enabled: true, targets: [target])
        let fixedNow = now
        let probe = NotificationDeliveryProbe()
        let service = NotificationService(configuration: { config }, now: { fixedNow }, read: { _ in throw URLError(.timedOut) })
        service.didReceive(request(), withContentHandler: { probe.record($0) })
        #expect(await probe.first() == .unavailable)
        #expect(probe.count == 1)
    }

    @Test func actualExpirationCompletesSynchronouslyAndCancelsInFlightRead() async {
        let config = FleetScheduledCheckConfiguration(enabled: true, targets: [target])
        let fixedNow = now
        let started = AsyncStream<Void>.makeStream()
        let cancelled = AsyncStream<Void>.makeStream()
        let probe = NotificationDeliveryProbe()
        let service = NotificationService(configuration: { config }, now: { fixedNow }, read: { _ in
            started.continuation.yield(())
            started.continuation.finish()
            do {
                try await Task.sleep(for: .seconds(60))
                Issue.record("Expiration did not cancel the LAN operation")
                return .init(hashRateGHs: 2000)
            } catch {
                cancelled.continuation.yield(())
                cancelled.continuation.finish()
                throw error
            }
        })
        service.didReceive(request(), withContentHandler: { probe.record($0) })
        for await _ in started.stream { break }
        service.serviceExtensionTimeWillExpire()
        #expect(probe.count == 1)
        #expect(await probe.first() == .unavailable)
        for await _ in cancelled.stream { break }
        service.serviceExtensionTimeWillExpire()
        #expect(probe.count == 1)
    }
}

/// All callback state is synchronized; only Sendable strings/presentations leave the lock.
private final class NotificationDeliveryProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [FleetScheduledCheckPresentation] = []
    private var categoryValues: [String] = []
    private var waiter: CheckedContinuation<FleetScheduledCheckPresentation, Never>?
    func record(_ content: UNNotificationContent) {
        let result = FleetScheduledCheckPresentation(title: content.title, body: content.body)
        let waiting = lock.withLock {
            results.append(result)
            categoryValues.append(content.categoryIdentifier)
            let current = waiter
            waiter = nil
            return current
        }
        waiting?.resume(returning: result)
    }
    func first() async -> FleetScheduledCheckPresentation {
        await withCheckedContinuation { continuation in
            let existing = lock.withLock { () -> FleetScheduledCheckPresentation? in
                if let first = results.first { return first }
                waiter = continuation
                return nil as FleetScheduledCheckPresentation?
            }
            if let existing { continuation.resume(returning: existing) }
        }
    }
    var count: Int { lock.withLock { results.count } }
    var titles: [String] { lock.withLock { results.map(\.title) } }
    var categories: [String] { lock.withLock { categoryValues } }
}
private final class CancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set(_ value: Bool) { lock.withLock { flag = value } }
    var value: Bool { lock.withLock { flag } }
}
