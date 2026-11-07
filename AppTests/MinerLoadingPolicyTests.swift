import Testing
import Foundation
import HashFleetCore
@testable import HashFleet

/// Tests validating loading state conditions and policy.
/// Initial loading skeletons should be displayed ONLY when:
/// 1. snapshot?.info == nil
/// 2. snapshot?.error == nil
/// 3. !isDemo
/// Cached/offline data (snapshot?.info != nil) MUST remain visible.
/// Failed empty state (snapshot?.error != nil) must not spin/skeletonize forever.
@Suite("Miner loading policy tests")
struct MinerLoadingPolicyTests {

    @Test("Initial loading requires no info, no error, and not demo")
    func testInitialLoadingCondition() {
        // Initial connecting state -> should skeleton
        #expect(MinerLoadingPolicy.shouldShowSkeleton(info: nil, error: nil, isDemo: false) == true)

        // Demo mode -> never skeleton
        #expect(MinerLoadingPolicy.shouldShowSkeleton(info: nil, error: nil, isDemo: true) == false)

        // Error present -> do not skeleton (surface error instead of perpetual skeleton)
        #expect(MinerLoadingPolicy.shouldShowSkeleton(info: nil, error: "Connection refused", isDemo: false) == false)
        #expect(MinerLoadingPolicy.shouldShowSkeleton(info: nil, error: "Connection refused", isDemo: true) == false)
    }

    @Test("Cached or offline data with previous info remains visible")
    func testCachedOrOfflineDataPreserved() {
        let dummyJSON = """
            {"hostname":"Rig1","ASICModel":"BM1366","hashRate":500.0,"power":12.5,"temp":55.0,"fanspeed":70}
            """
        let data = Data(dummyJSON.utf8)
        let info = try? JSONDecoder().decode(MinerInfo.self, from: data)
        #expect(info != nil)

        // Online with info -> no skeleton
        #expect(MinerLoadingPolicy.shouldShowSkeleton(info: info, error: nil, isDemo: false) == false)

        // Offline with error but cached info -> no skeleton (cached data remains visible)
        #expect(MinerLoadingPolicy.shouldShowSkeleton(info: info, error: "Timeout", isDemo: false) == false)
    }
}
