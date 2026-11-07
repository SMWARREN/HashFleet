import Foundation
import HashFleetCore
@testable import HashFleetMac

// Compile against the native Debug module. Synthetic data only. No app activation or I/O.
let now = Date(timeIntervalSince1970: 1_800_000_000.5)
let stored = (0..<110_000).map { index in
    HashratePoint(date: now.addingTimeInterval(-86_399 + Double(index) * 0.78), value: 1_000 + Double(index % 71))
}
let current = (0..<360).map { index in
    HashratePoint(date: now.addingTimeInterval(-359 + Double(index)), value: 1_100 + Double(index % 29))
}
let ids = (0..<4).map { _ in UUID() }
let identity = FleetHistoryRangeIdentity(
    kind: .sha256,
    currentSignatures: ids.map { MinerHistorySignature(id: $0, history: current, updatedAt: now) },
    storedSignatures: ids.map { MinerHistorySignature(id: $0, history: stored) },
    storedRevision: 1
)
let cache = FleetHistoryRangeCache()
var derivations = 0
let make = {
    derivations += 1
    let points = ids.flatMap { _ in
        FleetHistorySource.mergedPoints(stored: stored, current: current,
            since: now.addingTimeInterval(-86_400), until: now)
    }
    return (ranges: FleetHistoryPresentation.availableRecentRanges(for: points, now: now),
            expiration: FleetHistorySource.recentRangeExpiration(sources: [stored, current], now: now))
}
let start = ContinuousClock.now
let cold = cache.resolve(identity, now: now, make: make)
let coldTime = start.duration(to: .now)
let warmStart = ContinuousClock.now
for _ in 0..<10_000 {
    precondition(cache.resolve(identity, now: now.addingTimeInterval(0.1), make: make) == cold)
}
let warmTime = warmStart.duration(to: .now)
precondition(derivations == 1)
print("four miners x 110000 stored points, cold=\(coldTime), warm10000=\(warmTime), derivations=\(derivations)")
