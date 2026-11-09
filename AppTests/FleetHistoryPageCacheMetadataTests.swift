import Foundation
import SwiftUI
import Testing
#if os(macOS)
@testable import HashFleetMac
#else
@testable import HashFleet
#endif
import HashFleetCore

/// Unit-level regression tests for `FleetHistoryCard.pageData(for:cache:)` cache metadata invalidation.
///
/// Background:
/// `FleetHistoryPageCache` caches `PageData` keyed by `FleetHistoryPageIdentity`.
/// `FleetHistoryCard.minerSeries(for:)` builds display series whose labels depend on:
/// - `device.name`
/// - Disambiguated `\(device.name) · \(device.address)` when duplicate names exist
///
/// In the unpatched implementation, `FleetHistoryPageIdentity` omits device metadata (`name`, `address`, `kind`),
/// causing two cards evaluated against the same `FleetHistoryPageCache` instance with identical history snapshots/signatures
/// but modified device metadata to evaluate `identityA == identityB`, returning stale cached `PageData`.
///
/// These tests evaluate pure dataflow through `FleetHistoryCard.pageData(for:cache:)`
/// using real `minerSeries` execution, safely recent fixed dates, `initialDisplay: .miners`, and `isDemo: true`.
///
/// Test architecture:
/// - A shared `FleetHistoryPageCache` instance is passed explicitly into `cardA.pageData(for: .daily, cache: sharedCache)`
///   and `cardB.pageData(for: .daily, cache: sharedCache)`.
/// - Cards share identical snapshot history and timestamps.
/// - Unpatched code: `identityA == identityB` -> `cardB.pageData(for:cache:)` returns stale series from `cardA`.
/// - Patched code (with device metadata in identity): `identityA != identityB` -> cache invalidates and returns fresh series.
///
/// Scope & Boundary:
/// - Evaluates pure SwiftUI view dataflow and cache identity invariants without manual identity construction.
/// - This is a dataflow regression test, not rendered AttributeGraph / UI lifecycle evidence.
@MainActor
@Suite("FleetHistoryCard PageData Cache Metadata Regression", .serialized)
struct FleetHistoryPageCacheMetadataTests {

    private static func makeSnapshots(
        for devices: [MinerDevice],
        anchor: Date,
        historyCount: Int = 10
    ) -> [UUID: MinerSnapshot] {
        var snapshots: [UUID: MinerSnapshot] = [:]
        for (deviceIndex, device) in devices.enumerated() {
            let points: [HashratePoint] = (0..<historyCount).map { i in
                // Points within the last 60 seconds (well within the daily window's recentRange)
                let date = anchor.addingTimeInterval(-Double(historyCount - i) * 2.0)
                let rate = 1_000.0 + Double(deviceIndex * 100) + Double(i)
                return HashratePoint(date: date, value: rate)
            }
            snapshots[device.id] = MinerSnapshot(
                info: nil,
                previousInfo: nil,
                error: nil,
                updatedAt: anchor,
                completeSnapshotAt: anchor,
                powerObservedAt: nil,
                history: points,
                isCached: false,
                isReconnecting: false
            )
        }
        return snapshots
    }

    private static func makeCard(
        devices: [MinerDevice],
        snapshots: [UUID: MinerSnapshot]
    ) -> FleetHistoryCard {
        FleetHistoryCard(
            devices: devices,
            snapshots: snapshots,
            isDemo: true,
            initialDisplay: .miners,
            initialRecentRange: .hour,
            database: nil,
            isMinerDetail: false,
            isCompactDashboard: false
        )
    }

    // MARK: - Test 1: Device Name Mutation (Same UUID & History)

    @Test
    func deviceNameMutationInvalidatesPageDataCache() {
        let deviceID = UUID()
        let fixedNow = Date()

        let deviceA = MinerDevice(id: deviceID, name: "Alpha", address: "192.168.1.100", kind: .espMiner)
        let deviceB = MinerDevice(id: deviceID, name: "Beta", address: "192.168.1.100", kind: .espMiner)

        let snapshots = Self.makeSnapshots(for: [deviceA], anchor: fixedNow)
        let sharedCache = FleetHistoryPageCache()
        let cardA = Self.makeCard(devices: [deviceA], snapshots: snapshots)
        let cardB = Self.makeCard(devices: [deviceB], snapshots: snapshots)

        let pageDataA = cardA.pageData(for: .daily, cache: sharedCache)
        #expect(pageDataA.histories.count == 1)
        #expect(pageDataA.histories.first?.name == "Alpha")

        let pageDataB = cardB.pageData(for: .daily, cache: sharedCache)
        #expect(pageDataB.histories.count == 1)
        // With cache invalidation on metadata change, cardB must produce the updated device name "Beta".
        // Before the metadata fix, cardB returns the cached "Alpha" series because history signatures match.
        #expect(pageDataB.histories.first?.name == "Beta")
    }

    // MARK: - Test 2: Duplicate Name Introduction (Disambiguation Label)

    @Test
    func duplicateNameIntroductionCausesDisambiguationInvalidation() {
        let id1 = UUID()
        let id2 = UUID()
        let fixedNow = Date()

        // State A: Distinct names
        let devA1 = MinerDevice(id: id1, name: "Miner-Alpha", address: "192.168.1.101", kind: .espMiner)
        let devA2 = MinerDevice(id: id2, name: "Miner-Beta", address: "192.168.1.102", kind: .espMiner)

        // State B: dev2 renamed to match dev1 name -> triggers `duplicateName ? "\(name) · \(address)" : name`
        let devB1 = MinerDevice(id: id1, name: "Miner-Alpha", address: "192.168.1.101", kind: .espMiner)
        let devB2 = MinerDevice(id: id2, name: "Miner-Alpha", address: "192.168.1.102", kind: .espMiner)

        let snapshots = Self.makeSnapshots(for: [devA1, devA2], anchor: fixedNow)
        let sharedCache = FleetHistoryPageCache()
        let cardA = Self.makeCard(devices: [devA1, devA2], snapshots: snapshots)
        let cardB = Self.makeCard(devices: [devB1, devB2], snapshots: snapshots)

        let pageDataA = cardA.pageData(for: .daily, cache: sharedCache)
        let namesA = pageDataA.histories.map(\.name)
        #expect(namesA == ["Miner-Alpha", "Miner-Beta"])

        let pageDataB = cardB.pageData(for: .daily, cache: sharedCache)
        let namesB = pageDataB.histories.map(\.name)
        // When dev2 adopts "Miner-Alpha", both devices become duplicate-named.
        // With metadata invalidation, cardB reflects the disambiguated address suffixes.
        // Before the metadata fix, cardB returns the cached distinct names because history signatures match.
        #expect(namesB == ["Miner-Alpha · 192.168.1.101", "Miner-Alpha · 192.168.1.102"])
    }

    // MARK: - Test 3: Duplicate Name Resolution (Disambiguation Removal)

    @Test
    func duplicateNameResolutionRemovesDisambiguationInPageDataCache() {
        let id1 = UUID()
        let id2 = UUID()
        let fixedNow = Date()

        // State A: Duplicate names -> both disambiguated with address
        let devA1 = MinerDevice(id: id1, name: "Miner-One", address: "192.168.1.101", kind: .espMiner)
        let devA2 = MinerDevice(id: id2, name: "Miner-One", address: "192.168.1.102", kind: .espMiner)

        // State B: dev2 renamed to distinct name -> disambiguation resolved
        let devB1 = MinerDevice(id: id1, name: "Miner-One", address: "192.168.1.101", kind: .espMiner)
        let devB2 = MinerDevice(id: id2, name: "Miner-Two", address: "192.168.1.102", kind: .espMiner)

        let snapshots = Self.makeSnapshots(for: [devA1, devA2], anchor: fixedNow)
        let sharedCache = FleetHistoryPageCache()
        let cardA = Self.makeCard(devices: [devA1, devA2], snapshots: snapshots)
        let cardB = Self.makeCard(devices: [devB1, devB2], snapshots: snapshots)

        let pageDataA = cardA.pageData(for: .daily, cache: sharedCache)
        let namesA = pageDataA.histories.map(\.name)
        #expect(namesA == ["Miner-One · 192.168.1.101", "Miner-One · 192.168.1.102"])

        let pageDataB = cardB.pageData(for: .daily, cache: sharedCache)
        let namesB = pageDataB.histories.map(\.name)
        #expect(namesB == ["Miner-One", "Miner-Two"])
    }

    // MARK: - Test 4: Device Address Mutation on Duplicate-Named Miner

    @Test
    func deviceAddressMutationOnDuplicateNamedMinerInvalidatesPageDataCache() {
        let id1 = UUID()
        let id2 = UUID()
        let fixedNow = Date()

        // State A: Two miners with same name, dev1 at .101
        let devA1 = MinerDevice(id: id1, name: "Shared-Name", address: "192.168.1.101", kind: .espMiner)
        let devA2 = MinerDevice(id: id2, name: "Shared-Name", address: "192.168.1.102", kind: .espMiner)

        // State B: dev1 address changes to .199, name still duplicate
        let devB1 = MinerDevice(id: id1, name: "Shared-Name", address: "192.168.1.199", kind: .espMiner)
        let devB2 = MinerDevice(id: id2, name: "Shared-Name", address: "192.168.1.102", kind: .espMiner)

        let snapshots = Self.makeSnapshots(for: [devA1, devA2], anchor: fixedNow)
        let sharedCache = FleetHistoryPageCache()
        let cardA = Self.makeCard(devices: [devA1, devA2], snapshots: snapshots)
        let cardB = Self.makeCard(devices: [devB1, devB2], snapshots: snapshots)

        let pageDataA = cardA.pageData(for: .daily, cache: sharedCache)
        let namesA = pageDataA.histories.map(\.name)
        #expect(namesA == ["Shared-Name · 192.168.1.101", "Shared-Name · 192.168.1.102"])

        let pageDataB = cardB.pageData(for: .daily, cache: sharedCache)
        let namesB = pageDataB.histories.map(\.name)
        #expect(namesB == ["Shared-Name · 192.168.1.199", "Shared-Name · 192.168.1.102"])
    }

    // MARK: - Test 5: Positive Control - Device Ordering Preserved in Signatures

    @Test
    func deviceOrderingChangeAlreadyInvalidatesIdentityThroughSignatures() {
        let id1 = UUID()
        let id2 = UUID()
        let fixedNow = Date()

        let dev1 = MinerDevice(id: id1, name: "First", address: "192.168.1.101", kind: .espMiner)
        let dev2 = MinerDevice(id: id2, name: "Second", address: "192.168.1.102", kind: .espMiner)

        let snapshots = Self.makeSnapshots(for: [dev1, dev2], anchor: fixedNow)
        let sharedCache = FleetHistoryPageCache()

        // Card A: [dev1, dev2]
        // Card B: [dev2, dev1] - device ordering reversed
        let cardA = Self.makeCard(devices: [dev1, dev2], snapshots: snapshots)
        let cardB = Self.makeCard(devices: [dev2, dev1], snapshots: snapshots)

        let pageDataA = cardA.pageData(for: .daily, cache: sharedCache)
        #expect(pageDataA.histories.map(\.id) == [id1, id2])

        // Device ordering changes the order of elements in `historySignatures` (devices.map { ... }).
        // Because Array equality is order-sensitive, identityA != identityB even in unpatched code.
        // This serves as an existing positive control confirming signature-driven invalidation.
        let pageDataB = cardB.pageData(for: .daily, cache: sharedCache)
        #expect(pageDataB.histories.map(\.id) == [id2, id1])
    }

    // MARK: - Test 6: Device Kind Mutation (Same Two IDs & Signatures, activeKind .sha256 on both)

    @Test
    func deviceKindMutationInvalidatesPageDataCacheWhenActiveKindMatches() {
        let id1 = UUID()
        let id2 = UUID()
        let fixedNow = Date()

        // Card A: dev1 is .espMiner, dev2 is .xmrig.
        // activeKind evaluates to .sha256 (available: [.sha256, .cpu], first is .sha256).
        // chartDevices for activeKind (.sha256) contains only dev1.
        let devA1 = MinerDevice(id: id1, name: "Miner-1", address: "192.168.1.101", kind: .espMiner)
        let devA2 = MinerDevice(id: id2, name: "Miner-2", address: "192.168.1.102", kind: .xmrig)

        // Card B: dev2 kind mutates to .espMiner with identical UUID, history, and timestamps.
        // activeKind evaluates to .sha256 (available: [.sha256], first is .sha256).
        // chartDevices for activeKind (.sha256) now contains BOTH dev1 and dev2.
        let devB1 = MinerDevice(id: id1, name: "Miner-1", address: "192.168.1.101", kind: .espMiner)
        let devB2 = MinerDevice(id: id2, name: "Miner-2", address: "192.168.1.102", kind: .espMiner)

        // Snapshots and history signatures are identical for both cards across both IDs
        let snapshots = Self.makeSnapshots(for: [devA1, devA2], anchor: fixedNow)
        let sharedCache = FleetHistoryPageCache()

        let cardA = Self.makeCard(devices: [devA1, devA2], snapshots: snapshots)
        let cardB = Self.makeCard(devices: [devB1, devB2], snapshots: snapshots)

        #expect(cardA.activeKind == .sha256)
        #expect(cardB.activeKind == .sha256)

        // In Card A: only dev1 matches activeKind (.sha256), so pageData contains only dev1
        let pageDataA = cardA.pageData(for: .daily, cache: sharedCache)
        #expect(pageDataA.histories.map(\.id) == [id1])

        // In Card B: dev2 kind mutated to .espMiner, so chartDevices now includes dev2.
        // With cache invalidation on metadata change, cardB must produce histories for both [id1, id2].
        // Before the metadata fix, cardB returns cached pageDataA (only [id1]) because
        // activeKind (.sha256), history signatures ([id1, id2]), and window/revision are identical!
        let pageDataB = cardB.pageData(for: .daily, cache: sharedCache)
        #expect(pageDataB.histories.map(\.id) == [id1, id2])
    }
}
