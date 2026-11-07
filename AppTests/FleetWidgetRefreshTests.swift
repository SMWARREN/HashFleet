import Foundation
import Darwin
import Testing
import HashFleetCore
@testable import HashFleet

@Suite("Transactional widget local refresh", .serialized)
struct FleetWidgetRefreshTests: Sendable {
    private let date = Date(timeIntervalSince1970: 1_793_200_000)

    @Test func absentMalformedAndOversizedStateNeverStartsReads() async throws {
        let fixture = try WidgetRefreshFixture()
        defer { fixture.clear() }
        let calls = WidgetRefreshCalls()
        let runner = FleetWidgetRefreshRunner(storage: fixture.storage, read: { _ in
            await calls.increment()
            return .init(hashRateGHs: 1_200, powerW: 19)
        }, now: { date })
        #expect(fixture.storage.load() == nil)
        #expect(await runner.refresh() == .needsSetup)
        for data in [Data("{}".utf8), Data(repeating: 32, count: 65_537)] {
            try data.write(to: fixture.file)
            #expect(fixture.storage.load() == nil)
            #expect(await runner.refresh() == .needsSetup)
        }
        #expect(await calls.value == 0)
        let unavailable = HashFleet.FleetWidgetRefreshStorage(directory: nil)
        #expect(!unavailable.configure(targets: [widgetRefreshTarget()], now: date))
        #expect(unavailable.load() == nil)
        #expect(await FleetWidgetRefreshRunner(storage: unavailable, read: { _ in
            await calls.increment(); return .init(hashRateGHs: 1, powerW: 1)
        }).refresh() == .unavailable)
        #expect(await calls.value == 0)
    }

    @Test(arguments: ["http://miner.local", "http://8.8.8.8", "http://127.0.0.1", "http://169.254.1.1",
        "http://[fd00::1]", "http://10.1.1.1/api", "http://user:fixture@10.1.1.1", "http://10.1.1.1?x=1"])
    func onlyLiteralPrivateRootEndpointsAreAccepted(url: String) throws {
        let fixture = try WidgetRefreshFixture()
        defer { fixture.clear() }
        #expect(!fixture.storage.configure(targets: [widgetRefreshTarget(url: url)], now: date))
        #expect(fixture.storage.load() == nil)
    }

    @Test func duplicatesEmptyAndOversizedInventoriesAreRejectedWithoutCrashing() throws {
        let fixture = try WidgetRefreshFixture()
        defer { fixture.clear() }
        let a = widgetRefreshTarget()
        for targets in [[], [a, a], [a, widgetRefreshTarget(2, id: a.id)],
            [a, widgetRefreshTarget(2, url: a.baseURL.absoluteString + "/")],
            [a, widgetRefreshTarget(2, url: a.baseURL.absoluteString + ":80")],
            [widgetRefreshTarget(url: "https://10.23.45.1"), widgetRefreshTarget(2, url: "https://10.23.45.1:443/")],
            [a, widgetRefreshTarget(2, mac: a.expectedMAC)], (1...17).map { widgetRefreshTarget($0) }] {
            #expect(!fixture.storage.configure(targets: targets, now: date))
            #expect(fixture.storage.load() == nil)
        }
    }

    @Test func completeZeroReadingsAreRealAndConfigurationIsStableUntilItChanges() async throws {
        let fixture = try WidgetRefreshFixture()
        defer { fixture.clear() }
        let targets = [widgetRefreshTarget(), widgetRefreshTarget(2)]
        #expect(fixture.storage.configure(targets: targets, now: date))
        let first = try #require(fixture.storage.load())
        #expect(fixture.storage.configure(targets: Array(targets.reversed()), now: date.addingTimeInterval(30)))
        #expect(fixture.storage.load() == first)
        #expect(fixture.storage.configure(targets: targets, now: date.addingTimeInterval(3_600)))
        let renewed = try #require(fixture.storage.load())
        #expect(renewed.configuration.generation == first.configuration.generation)
        #expect(renewed.configuration.expiresAt == date.addingTimeInterval(3_600 + 86_400))
        let observed = date.addingTimeInterval(3_601)
        let zeroRunner = FleetWidgetRefreshRunner(storage: fixture.storage, read: { target in
            #expect(target.name == "Miner")
            #expect(target.isValid)
            return .init(hashRateGHs: 0, powerW: 0)
        }, now: { observed })
        #expect(await zeroRunner.refresh() == .refreshed)
        let state = try #require(fixture.storage.load())
        #expect(state.glance?.onlineCount == 2 && state.glance?.minerCount == 2)
        #expect(state.glance?.hashrateGHs == 0 && state.glance?.powerWatts == 0)
        #expect(state.glance?.updatedAt == observed)
        #expect(state.lastOutcome == .refreshed)
        #expect(state.lease == nil)
        #expect(fixture.storage.configure(targets: [widgetRefreshTarget(3)], now: observed))
        #expect(fixture.storage.load()?.configuration.generation != first.configuration.generation)
        #expect(fixture.storage.load()?.glance == nil)
    }

    @Test(arguments: [6.0, 60.0, 3_600.0])
    func renewedPermissionCannotStartReadsBeforeItsRenewalAfterClockRollback(seconds: TimeInterval) async throws {
        let fixture = try WidgetRefreshFixture()
        defer { fixture.clear() }
        let targets = [widgetRefreshTarget()]
        #expect(fixture.storage.configure(targets: targets, now: date.addingTimeInterval(-7_200)))
        #expect(fixture.storage.configure(targets: targets, now: date))
        let renewed = try #require(fixture.storage.load()?.configuration)
        #expect(renewed.renewedAt == date)
        let rolledBack = date.addingTimeInterval(-seconds)
        #expect(!renewed.isEnabled(at: rolledBack))
        let calls = WidgetRefreshCalls()
        #expect(await FleetWidgetRefreshRunner(storage: fixture.storage, read: { _ in
            await calls.increment()
            return .init(hashRateGHs: 1_200, powerW: 19)
        }, now: { rolledBack }).refresh() == .needsSetup)
        #expect(await calls.value == 0)
        #expect(fixture.storage.load()?.glance == nil)
        #expect(fixture.storage.load()?.lease == nil)
        // Fresh foreground preparation at the corrected clock must rotate the old permission.
        #expect(fixture.storage.configure(targets: targets, now: rolledBack))
        let replacement = try #require(fixture.storage.load()?.configuration)
        #expect(replacement.generation != renewed.generation)
        #expect(replacement.renewedAt == rolledBack)
        #expect(replacement.expiresAt == rolledBack.addingTimeInterval(86_400))
        #expect(replacement.isEnabled(at: rolledBack))
    }

    @Test func renewalClockLeewayAndExpiryHaveExactBoundaries() throws {
        let fixture = try WidgetRefreshFixture()
        defer { fixture.clear() }
        let targets = [widgetRefreshTarget()]
        #expect(fixture.storage.configure(targets: targets, now: date.addingTimeInterval(-7_200)))
        #expect(fixture.storage.configure(targets: targets, now: date))
        let configuration = try #require(fixture.storage.load()?.configuration)
        #expect(configuration.isEnabled(at: date.addingTimeInterval(-5)))
        #expect(!configuration.isEnabled(at: date.addingTimeInterval(-5.001)))
        #expect(configuration.isEnabled(at: date.addingTimeInterval(86_399.999)))
        #expect(!configuration.isEnabled(at: date.addingTimeInterval(86_400)))
    }

    @Test func aFutureRenewalDuringAwaitCannotPublishUsingTheEarlierClock() async throws {
        let fixture = try WidgetRefreshFixture()
        defer { fixture.clear() }
        let targets = [widgetRefreshTarget()]
        #expect(fixture.storage.configure(targets: targets, now: date.addingTimeInterval(-7_200)))
        let generation = fixture.storage.load()?.configuration.generation
        let gate = WidgetRefreshGate()
        let task = Task {
            await FleetWidgetRefreshRunner(storage: fixture.storage, read: { _ in
                await gate.pause()
                return .init(hashRateGHs: 1_200, powerW: 19)
            }, now: { date }).refresh()
        }
        await gate.waitForEntry()
        #expect(fixture.storage.configure(targets: targets, now: date.addingTimeInterval(3_600)))
        #expect(fixture.storage.load()?.configuration.generation == generation)
        await gate.release()
        #expect(await task.value == .needsSetup)
        #expect(fixture.storage.load()?.glance == nil)
    }

    @Test func failedPartialAndTimedOutAttemptsKeepThePreviousReadingAndTime() async throws {
        let fixture = try WidgetRefreshFixture()
        defer { fixture.clear() }
        #expect(fixture.storage.configure(targets: [widgetRefreshTarget()], now: date))
        #expect(await FleetWidgetRefreshRunner(storage: fixture.storage, read: { _ in
            .init(hashRateGHs: 1_200, powerW: 19)
        }, now: { date }).refresh() == .refreshed)
        let previous = try #require(fixture.storage.load()?.glance)
        for (index, read) in [
            { @Sendable (_: FleetScheduledCheckTarget) async throws -> FleetScheduledCheckReading in
                throw URLError(.notConnectedToInternet)
            },
            { @Sendable (_: FleetScheduledCheckTarget) async throws -> FleetScheduledCheckReading in
                .init(hashRateGHs: 1_900, powerW: nil)
            },
            { @Sendable (_: FleetScheduledCheckTarget) async throws -> FleetScheduledCheckReading in
                try await Task.sleep(for: .seconds(30)); return .init(hashRateGHs: 9_999, powerW: 999)
            }
        ].enumerated() {
            let later = date.addingTimeInterval(Double(index + 1) * 20)
            let outcome = await FleetWidgetRefreshRunner(storage: fixture.storage, read: read,
                now: { later }, timeout: .milliseconds(20)).refresh()
            #expect(outcome == (index == 2 ? .timedOut : .unavailable))
            #expect(fixture.storage.load()?.glance == previous)
            #expect(fixture.storage.load()?.glance?.updatedAt == date)
        }
    }

    @Test(arguments: [false, true])
    func revocationOrReconfigurationDuringAwaitCannotResurrectAnOldLease(reenable: Bool) async throws {
        let fixture = try WidgetRefreshFixture()
        defer { fixture.clear() }
        let target = widgetRefreshTarget()
        #expect(fixture.storage.configure(targets: [target], now: date))
        let generation = fixture.storage.load()?.configuration.generation
        let gate = WidgetRefreshGate()
        let task = Task {
            await FleetWidgetRefreshRunner(storage: fixture.storage, read: { _ in
                await gate.pause(); return .init(hashRateGHs: 1_200, powerW: 19)
            }, now: { date }).refresh()
        }
        await gate.waitForEntry()
        let lockPath = fixture.directory.appendingPathComponent(HashFleet.FleetWidgetRefreshStorage.lockFilename).path
        let before = try FileManager.default.attributesOfItem(atPath: lockPath)[.systemFileNumber] as? NSNumber
        #expect(fixture.storage.revoke())
        if reenable { #expect(fixture.storage.configure(targets: [target], now: date)) }
        await gate.release()
        #expect(await task.value == .needsSetup)
        if reenable {
            #expect(fixture.storage.load()?.configuration.generation != generation)
            #expect(fixture.storage.load()?.glance == nil)
        } else { #expect(fixture.storage.load() == nil) }
        let after = try FileManager.default.attributesOfItem(atPath: lockPath)[.systemFileNumber] as? NSNumber
        #expect(before == after, "Revocation must retain the fixed lock inode")
    }

    @Test func aSeparateStorageOwnerSeesTheLeaseAndCooldownAndCancellationPreservesTime() async throws {
        let fixture = try WidgetRefreshFixture()
        defer { fixture.clear() }
        #expect(fixture.storage.configure(targets: [widgetRefreshTarget()], now: date))
        let gate = WidgetRefreshGate()
        let calls = WidgetRefreshCalls()
        let task = Task {
            await FleetWidgetRefreshRunner(storage: fixture.storage, read: { _ in
                await gate.pause(); return .init(hashRateGHs: 1_200, powerW: 19)
            }, now: { date }).refresh()
        }
        await gate.waitForEntry()
        let second = HashFleet.FleetWidgetRefreshStorage(directory: fixture.directory)
        #expect(await FleetWidgetRefreshRunner(storage: second, read: { _ in
            await calls.increment(); return .init(hashRateGHs: 2_000, powerW: 20)
        }, now: { date }).refresh() == .busy)
        task.cancel()
        await gate.release()
        #expect(await task.value == .cancelled)
        #expect(fixture.storage.load()?.glance == nil)
        #expect(fixture.storage.load()?.lastOutcome == .cancelled)
        #expect(await FleetWidgetRefreshRunner(storage: second, read: { _ in
            await calls.increment(); return .init(hashRateGHs: 2_000, powerW: 20)
        }, now: { date }).refresh() == .busy)
        #expect(await calls.value == 0)
    }

    @Test func expiredConfigurationStartsNoReadsAndExpiredLeaseCanBeReplacedButNotPublished() async throws {
        let fixture = try WidgetRefreshFixture()
        defer { fixture.clear() }
        #expect(fixture.storage.configure(targets: [widgetRefreshTarget()], now: date))
        let gate = WidgetRefreshGate()
        let old = Task {
            await FleetWidgetRefreshRunner(storage: fixture.storage, read: { _ in
                await gate.pause(); return .init(hashRateGHs: 9_999, powerW: 999)
            }, now: { date }).refresh()
        }
        await gate.waitForEntry()
        let later = date.addingTimeInterval(16)
        #expect(await FleetWidgetRefreshRunner(storage: fixture.storage, read: { _ in
            .init(hashRateGHs: 1_200, powerW: 19)
        }, now: { later }).refresh() == .refreshed)
        await gate.release()
        #expect(await old.value == .needsSetup)
        #expect(fixture.storage.load()?.glance?.hashrateGHs == 1_200)
        let expired = date.addingTimeInterval(86_401)
        let calls = WidgetRefreshCalls()
        #expect(await FleetWidgetRefreshRunner(storage: fixture.storage, read: { _ in
            await calls.increment(); return .init(hashRateGHs: 3, powerW: 3)
        }, now: { expired }).refresh() == .needsSetup)
        #expect(await calls.value == 0)
    }

    @Test func maximumInventoryUsesAtMostFourConcurrentReadsWithoutRetries() async throws {
        let fixture = try WidgetRefreshFixture()
        defer { fixture.clear() }
        #expect(fixture.storage.configure(targets: (1...16).map { widgetRefreshTarget($0) }, now: date))
        let concurrency = WidgetRefreshConcurrency()
        let outcome = await FleetWidgetRefreshRunner(storage: fixture.storage, read: { _ in
            await concurrency.enter()
            try await Task.sleep(for: .milliseconds(10))
            await concurrency.leave()
            return .init(hashRateGHs: 100, powerW: 10)
        }, now: { date }).refresh()
        #expect(outcome == .refreshed)
        #expect(await concurrency.total == 16)
        #expect(await concurrency.peak <= 4)
        #expect(await concurrency.active == 0)
        #expect(fixture.storage.load()?.glance?.hashrateGHs == 1_600)
        #expect(fixture.storage.load()?.glance?.powerWatts == 160)
        #expect(fixture.storage.load()?.glance?.onlineCount == 16)
    }

    @Test func aHeldFileLockFailsClosedInsteadOfWaitingToStartNetworkWork() async throws {
        let fixture = try WidgetRefreshFixture()
        defer { fixture.clear() }
        #expect(fixture.storage.configure(targets: [widgetRefreshTarget()], now: date))
        let lock = fixture.directory.appendingPathComponent(HashFleet.FleetWidgetRefreshStorage.lockFilename)
        let fd = Darwin.open(lock.path, O_RDWR | O_EXLOCK | O_CLOEXEC)
        try #require(fd >= 0)
        let release = Task.detached {
            try? await Task.sleep(for: .milliseconds(250))
            Darwin.close(fd)
        }
        let calls = WidgetRefreshCalls()
        let outcome = await FleetWidgetRefreshRunner(storage: fixture.storage, read: { _ in
            await calls.increment()
            return .init(hashRateGHs: 1_200, powerW: 19)
        }, now: { date }).refresh()
        await release.value
        #expect(outcome == .unavailable)
        #expect(await calls.value == 0)
        #expect(fixture.storage.load()?.glance == nil)
        #expect(fixture.storage.load()?.lease == nil)
    }

    @Test func oneFailedTargetCannotPublishAPartialFleetAsFresh() async throws {
        let fixture = try WidgetRefreshFixture()
        defer { fixture.clear() }
        let targets = [widgetRefreshTarget(), widgetRefreshTarget(2)]
        #expect(fixture.storage.configure(targets: targets, now: date))
        #expect(await FleetWidgetRefreshRunner(storage: fixture.storage, read: { _ in
            .init(hashRateGHs: 100, powerW: 10)
        }, now: { date }).refresh() == .refreshed)
        let previous = try #require(fixture.storage.load()?.glance)
        let later = date.addingTimeInterval(20)
        #expect(await FleetWidgetRefreshRunner(storage: fixture.storage, read: { target in
            if target.id == targets[1].id { throw URLError(.cannotConnectToHost) }
            return .init(hashRateGHs: 9_999, powerW: 999)
        }, now: { later }).refresh() == .unavailable)
        #expect(fixture.storage.load()?.glance == previous)
        #expect(fixture.storage.load()?.lastOutcome == .unavailable)
    }
}

actor WidgetRefreshConcurrency {
    private(set) var active = 0
    private(set) var peak = 0
    private(set) var total = 0
    func enter() {
        active += 1
        total += 1
        peak = max(peak, active)
    }
    func leave() { active -= 1 }
}

@Suite("Automatic widget refresh consent", .serialized)
struct FleetAutomaticRefreshConsentTests: Sendable {
    private let date = Date(timeIntervalSince1970: 1_793_200_000)

    @Test func existingManualPayloadCannotStartAutomaticReads() async throws {
        let fixture = try WidgetRefreshFixture()
        defer { fixture.clear() }
        #expect(fixture.storage.configure(targets: [widgetRefreshTarget()], now: date))
        // Encode without the newly introduced optional key, as an installed manual-only payload.
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.file)) as? [String: Any])
        var configuration = try #require(json["configuration"] as? [String: Any])
        configuration.removeValue(forKey: "automaticRefreshGeneration")
        json["configuration"] = configuration
        try JSONSerialization.data(withJSONObject: json).write(to: fixture.file)
        let calls = WidgetRefreshCalls()
        let runner = FleetWidgetRefreshRunner(storage: fixture.storage, read: { _ in
            await calls.increment()
            return .init(hashRateGHs: 1, powerW: 1)
        }, now: { date })
        #expect(fixture.storage.load()?.configuration.automaticRefreshGeneration == nil)
        #expect(await runner.refresh(automatically: true) == .needsSetup)
        #expect(await calls.value == 0)
        #expect(await runner.refresh() == .refreshed)
        #expect(await calls.value == 1)
    }

    @Test(arguments: [false, true])
    func automaticOptOutAndReenableBlockAnAwaitingRead(reenable: Bool) async throws {
        let fixture = try WidgetRefreshFixture()
        defer { fixture.clear() }
        #expect(fixture.storage.configure(targets: [widgetRefreshTarget()], now: date, automatically: true))
        let initial = try #require(fixture.storage.load()?.configuration)
        let gate = WidgetRefreshGate()
        let run = Task {
            await FleetWidgetRefreshRunner(storage: fixture.storage, read: { _ in
                await gate.pause()
                return .init(hashRateGHs: 1, powerW: 1)
            }, now: { date }).refresh(automatically: true)
        }
        await gate.waitForEntry()
        #expect(fixture.storage.setAutomaticRefreshEnabled(false, now: date))
        if reenable { #expect(fixture.storage.setAutomaticRefreshEnabled(true, now: date)) }
        await gate.release()
        #expect(await run.value == .needsSetup)
        let state = try #require(fixture.storage.load())
        #expect(state.glance == nil && state.lease == nil)
        #expect(state.configuration.generation == initial.generation)
        #expect(state.configuration.expiresAt == initial.expiresAt)
        #expect(state.configuration.automaticRefreshGeneration != initial.automaticRefreshGeneration)
    }

    @Test func automaticOptOutPreservesAnAuthenticatedManualReadAndBasePermission() async throws {
        let fixture = try WidgetRefreshFixture()
        defer { fixture.clear() }
        #expect(fixture.storage.configure(targets: [widgetRefreshTarget()], now: date, automatically: true))
        let initial = try #require(fixture.storage.load()?.configuration)
        let gate = WidgetRefreshGate()
        let run = Task {
            await FleetWidgetRefreshRunner(storage: fixture.storage, read: { _ in
                await gate.pause()
                return .init(hashRateGHs: 1, powerW: 1)
            }, now: { date }).refresh()
        }
        await gate.waitForEntry()
        #expect(fixture.storage.setAutomaticRefreshEnabled(false, now: date))
        await gate.release()
        #expect(await run.value == .refreshed)
        #expect(fixture.storage.load()?.configuration.generation == initial.generation)
        #expect(fixture.storage.load()?.configuration.expiresAt == initial.expiresAt)
        #expect(fixture.storage.load()?.configuration.automaticRefreshGeneration == nil)
    }

    @Test func automaticConsentCannotPrepareMissingOrRenewExpiredPins() throws {
        let fixture = try WidgetRefreshFixture()
        defer { fixture.clear() }
        #expect(!fixture.storage.setAutomaticRefreshEnabled(true, now: date))
        #expect(fixture.storage.configure(targets: [widgetRefreshTarget()], now: date))
        let initial = try #require(fixture.storage.load()?.configuration)
        #expect(fixture.storage.setAutomaticRefreshEnabled(true, now: date))
        #expect(fixture.storage.load()?.configuration.expiresAt == initial.expiresAt)
        #expect(!fixture.storage.setAutomaticRefreshEnabled(true, now: initial.expiresAt))
        #expect(fixture.storage.load()?.configuration.expiresAt == initial.expiresAt)
    }

    @Test func aCompletedAutomaticReceiptCannotPublishAfterAutomaticOptOut() async throws {
        let fixture = try WidgetRefreshFixture()
        defer { fixture.clear() }
        #expect(fixture.storage.configure(targets: [widgetRefreshTarget()], now: date, automatically: true))
        #expect(await FleetWidgetRefreshRunner(storage: fixture.storage, read: { _ in
            .init(hashRateGHs: 1, powerW: 1)
        }, now: { date }).refresh(automatically: true) == .refreshed)
        let state = try #require(fixture.storage.load())
        let publication = FleetActivityRefreshPublication(generation: state.configuration.generation,
            glance: try #require(state.glance), automaticRefreshGeneration: state.configuration.automaticRefreshGeneration)
        #expect(publication.isAuthorized(in: fixture.storage, at: date))
        #expect(fixture.storage.setAutomaticRefreshEnabled(false, now: date))
        #expect(!publication.isAuthorized(in: fixture.storage, at: date))
        #expect(!publication.hasCurrentPermission(in: fixture.storage, at: date))
        #expect(fixture.storage.load()?.glance == state.glance)
    }
}

struct WidgetRefreshFixture {
    let directory: URL
    let storage: HashFleet.FleetWidgetRefreshStorage
    var file: URL { directory.appendingPathComponent(HashFleet.FleetWidgetRefreshStorage.stateFilename) }
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("widget-refresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storage = .init(directory: directory)
    }
    func clear() { try? FileManager.default.removeItem(at: directory) }
}

func widgetRefreshTarget(_ index: Int = 1, id: UUID = UUID(), url: String? = nil, mac: String? = nil) -> HashFleet.FleetWidgetRefreshTarget {
    .init(id: id, baseURL: URL(string: url ?? "http://10.23.45.\(index)")!,
        expectedMAC: mac ?? String(format: "02:11:22:33:44:%02x", index))
}

actor WidgetRefreshCalls {
    private(set) var value = 0
    func increment() { value += 1 }
}

actor WidgetRefreshGate {
    private var entered = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var paused: CheckedContinuation<Void, Never>?
    func pause() async {
        entered = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
        await withCheckedContinuation { paused = $0 }
    }
    func waitForEntry() async {
        if entered { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() { paused?.resume(); paused = nil }
}
