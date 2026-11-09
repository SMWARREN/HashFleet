import Foundation
import Testing
@testable import HashFleetWatchCore

@MainActor
@Suite struct WatchFleetPollingTests {
    @Test func cadenceIsTenSecondsAndWaitFollowsEachFinishedRead() async {
        #expect(WatchFleetPolling.interval == .seconds(10))
        var events: [String] = []
        var reads = 0
        var sleeps = 0
        await WatchFleetPolling.run(refresh: {
            reads += 1
            events.append("start \(reads)")
            await Task.yield()
            events.append("finish \(reads)")
        }, sleep: {
            sleeps += 1
            events.append("wait \(sleeps)")
            if sleeps == 3 { throw CancellationError() }
        })
        #expect(events == ["start 1", "finish 1", "wait 1", "start 2", "finish 2", "wait 2", "start 3", "finish 3", "wait 3"])
    }

    @Test func cancellationDuringWaitDoesNotStartAnotherRead() async {
        var reads = 0
        let (started, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            await WatchFleetPolling.run(refresh: { reads += 1 }, sleep: {
                continuation.yield(())
                try await Task.sleep(for: .seconds(60))
            })
        }
        var iterator = started.makeAsyncIterator()
        await iterator.next()
        task.cancel()
        await task.value
        continuation.finish()
        #expect(reads == 1)
    }

    @Test func cancellationDuringReadSkipsTheWaitAndNextRead() async {
        var reads = 0
        var sleeps = 0
        let task = Task {
            await WatchFleetPolling.run(refresh: {
                reads += 1
                withUnsafeCurrentTask { $0?.cancel() }
            }, sleep: { sleeps += 1 })
        }
        await task.value
        #expect(reads == 1)
        #expect(sleeps == 0)
    }

    @Test func alreadyCancelledTaskDoesNotRead() async {
        var reads = 0
        let task = Task {
            await WatchFleetPolling.run(refresh: { reads += 1 }, sleep: { throw CancellationError() })
        }
        task.cancel()
        await task.value
        #expect(reads == 0)
    }

    @Test func demoIsNotPolledOrRestamped() async {
        let store = WatchFleetStore.demo()
        let before = store.readings
        await WatchFleetPolling.run(store: store)
        #expect(store.readings == before)
    }

    @Test(.timeLimit(.minutes(1))) func actualDefaultLoopReadsAgainAfterTenSeconds() async throws {
        let reader = ScriptedClient()
        let store = WatchFleetStore(storageURL: nil, client: reader)
        try store.addMiner(name: "Timer fixture", address: "192.168.1.31")
        let task = Task { await WatchFleetPolling.run(store: store) }
        defer { task.cancel() }
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(30)
        let minerID = store.miners[0].id
        while store.readings[minerID] == nil && clock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        let firstTime = try #require(store.readings[minerID]?.observedAt)
        while store.readings[minerID]?.observedAt == firstTime && clock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(await reader.fetchCount() == 2)
        task.cancel()
        await task.value
        let secondTime = try #require(store.readings[store.miners[0].id]?.observedAt)
        #expect(secondTime.timeIntervalSince(firstTime) >= 9.9)
        #expect(secondTime.timeIntervalSince(firstTime) < 30)
        #expect(await reader.peakConcurrency() == 1)
    }
}
