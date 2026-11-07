import Testing
@testable import HashFleetMac

@Suite("Native numeric motion")
struct FleetNativeNumericMotionTests {
    /// Native Mac rolls only headline hashrate numbers; secondary live labels update in place.
    @Test func nativeMacRollsHeadlineNumbersOnly() {
        #expect(FleetNumericMotionPolicy.updatesInPlace)
        #expect(!FleetNumericMotionPolicy.updatesInPlace(isHeadline: true))
        #expect(FleetNumericMotionPolicy.updatesInPlace(isNativeMac: true))
        #expect(!FleetNumericMotionPolicy.updatesInPlace(isNativeMac: true, isHeadline: true))
        #expect(!FleetNumericMotionPolicy.updatesInPlace(isNativeMac: false))
    }

    /// A forever-breathing Live badge on each card redrew at display rate and cost about 30%
    /// idle CPU on Overview with four miners. The Mac badge is steady; iOS keeps the breathing.
    @Test func nativeMacLiveBadgeIsSteady() {
        #expect(!FleetMinerStatusBadge.breathesWhileLive(isNativeMac: true))
        #expect(FleetMinerStatusBadge.breathesWhileLive(isNativeMac: false))
    }
}
