import Foundation
import UserNotifications
import HashFleetCore

/// This standard notification extension is launched only for a delivered mutable alert.
/// It is not a persistent process, a Local Push provider, or a LAN companion app.
final class NotificationService: UNNotificationServiceExtension, @unchecked Sendable {
    // All mutable extension state is owned by the internally locked slot/operation.
    private let slot = ScheduledNotificationSlot()
    private let configuration: @Sendable () -> FleetScheduledCheckConfiguration
    private let read: @Sendable (FleetScheduledCheckTarget) async throws -> FleetScheduledCheckReading
    private let now: @Sendable () -> Date

    override init() {
        configuration = { FleetScheduledCheckStorage.load(defaults: FleetSharedStore.defaults) }
        read = { try await FleetScheduledCheckReader().read($0) }
        now = { .now }
        super.init()
    }

    init(configuration: @escaping @Sendable () -> FleetScheduledCheckConfiguration,
         now: @escaping @Sendable () -> Date,
         read: @escaping @Sendable (FleetScheduledCheckTarget) async throws -> FleetScheduledCheckReading) {
        self.configuration = configuration
        self.now = now
        self.read = read
        super.init()
    }

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        let operation = ScheduledNotificationOperation(content: request.content, handler: contentHandler)
        slot.replace(with: operation)
        guard JSONSerialization.isValidJSONObject(request.content.userInfo),
              let data = try? JSONSerialization.data(withJSONObject: request.content.userInfo),
              let check = FleetScheduledCheckRequest.parse(data, now: now()) else {
            operation.finish(.unavailable)
            return
        }
        let configuration = self.configuration
        let read = self.read
        let now = self.now
        let task = Task {
            let result = await FleetScheduledCheckRunner.perform(request: check, configuration: configuration,
                now: now, read: read)
            operation.finish(result)
        }
        operation.install(task)
    }

    override func serviceExtensionTimeWillExpire() {
        slot.finishCurrent()
    }
}

/// The completion handler is claimed under a lock, then called outside it exactly once.
/// UNNotificationContent and the system callback never escape to an unprotected mutable field.
/// The task may finish before installation, or expiration may race any of these methods.
final class ScheduledNotificationOperation: @unchecked Sendable {
    private let lock = NSLock()
    private let content: UNNotificationContent
    private var handler: ((UNNotificationContent) -> Void)?
    private var task: Task<Void, Never>?

    init(content: UNNotificationContent, handler: @escaping (UNNotificationContent) -> Void) {
        self.content = (content.copy() as? UNNotificationContent) ?? UNNotificationContent()
        self.handler = handler
    }

    func install(_ newTask: Task<Void, Never>) {
        let shouldCancel = lock.withLock {
            guard handler != nil else { return true }
            task = newTask
            return false
        }
        if shouldCancel { newTask.cancel() }
    }

    func finish(_ result: FleetScheduledCheckPresentation) {
        let delivery = lock.withLock { () -> (((UNNotificationContent) -> Void), UNNotificationContent, Task<Void, Never>?)? in
            guard let callback = handler else { return nil }
            handler = nil
            let currentTask = task
            task = nil
            let updated = (content.mutableCopy() as? UNMutableNotificationContent) ?? UNMutableNotificationContent()
            updated.title = result.title
            updated.subtitle = ""
            updated.body = result.body
            updated.categoryIdentifier = "app.hashfleet.summary"
            updated.attachments = []
            return (callback, updated, currentTask)
        }
        guard let (callback, updated, currentTask) = delivery else { return }
        currentTask?.cancel()
        callback(updated)
    }
}

private final class ScheduledNotificationSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var operation: ScheduledNotificationOperation?
    func replace(with next: ScheduledNotificationOperation) {
        let old = lock.withLock {
            let previous = operation
            operation = next
            return previous
        }
        old?.finish(.unavailable)
    }
    func finishCurrent() {
        let current = lock.withLock { operation }
        current?.finish(.unavailable)
    }
}
