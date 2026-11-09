import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

@Suite("Reported miner state and alert tests")
struct MinerReportedStateTests {

    @Test func rotatingPoolUpdatesDashboardDetailDiagnosticsAndSetupWithoutFallbackFlagChanging() {
        var raw: [String: JSONValue] = [
            "primaryPoolIndex": .integer(0), "secondaryPoolIndex": .integer(1),
            "isUsingFallbackStratum": .integer(0), "poolRotationEnabled": .bool(true),
            "stratumURL": .string("stratum.ckpool.org"),
            "pools": .array([
                .object(["id": .integer(1), "stratumURL": .string("bch.solofury.com")]),
                .object(["id": .integer(0), "stratumURL": .string("stratum.ckpool.org")])
            ])
        ]
        for slot in [1, 0, 1] {
            raw["activePoolIndex"] = .integer(Int64(slot))
            let info = MinerInfo(raw: raw)
            let host = slot == 1 ? "bch.solofury.com" : "stratum.ckpool.org"
            let context = MinerMiningContext.resolve(info: info)
            #expect(context.headline == (slot == 1 ? "BCH · SoloFury" : "BTC · CKPool"))
            #expect(context.pool?.isActive == true)
            #expect(MinerActivePool(info: info).value == host)
            #expect(MinerActivePool(info: info).title == "Pool · active slot \(slot)")
            #expect(MinerDiagnosticsModel(raw: raw).pool.activeConnectionURL == host)
            let inventory = SoloPoolSlotInventory(raw: raw)
            #expect(inventory.slots.filter { $0.roleLabel.contains("in use") }.map(\.id) == [slot])
        }
        raw["activePoolIndex"] = .integer(7)
        #expect(MinerMiningContext.resolve(info: MinerInfo(raw: raw)).pool == nil)
        #expect(MinerActivePool(info: MinerInfo(raw: raw)).value == "Not reported")
        #expect(!SoloPoolSlotInventory(raw: raw).slots.contains { $0.roleLabel.contains("in use") })
    }

    // MARK: - Block Evidence Tests

    @Test func blockEventRequiresAnExplicitCounterIncreaseAndCarriesOnlySafeContext() throws {
        let device = MinerDevice(
            id: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            name: "Gamma 601",
            address: "http://192.168.1.601"
        )
        let baseline = MinerInfo(raw: [
            "blockFound": .integer(1),
            "bestDiff": .string("10"),
            "networkDifficulty": .string("100"),
            "uptimeSeconds": .integer(1_000),
            "isUsingFallbackStratum": .bool(false),
            "stratumURL": .string("stratum+tcp://stratum.ckpool.org:3333")
        ])
        let increased = MinerInfo(raw: [
            "blockFound": .integer(2),
            "blockHeight": .integer(900_001),
            // Best share meets the network target: a genuine solve.
            "bestDiff": .string("150"),
            "networkDifficulty": .string("100"),
            "uptimeSeconds": .integer(1_030),
            "isUsingFallbackStratum": .bool(false),
            "stratumURL": .string("stratum+tcp://stratum.ckpool.org:3333"),
            "stratumUser": .string("wallet.worker")
        ])

        #expect(
            MinerBlockFoundEvent.detect(device: device, previous: nil, current: baseline, occurredAt: Date()) == nil
        )
        let event = try #require(
            MinerBlockFoundEvent.detect(device: device, previous: baseline, current: increased, occurredAt: Date())
        )
        #expect(event.coinLabel == "BTC")
        #expect(event.height == 900_001)
        #expect(event.count == 2)
        #expect(event.minerName == "Gamma 601")
    }

    @Test func counterIncreaseAcrossARebootDoesNotFireABlockEvent() {
        let device = MinerDevice(name: "Gamma", address: "http://192.168.1.60")
        // The blockFound counter resets to 0 on reboot then re-climbs. A rise from 0 -> 1
        // paired with a lower uptime must not be reported as a block.
        let before = MinerInfo(raw: [
            "blockFound": .integer(4),
            "bestDiff": .string("500"),
            "networkDifficulty": .string("100"),
            "uptimeSeconds": .integer(50_000)
        ])
        let afterReboot = MinerInfo(raw: [
            "blockFound": .integer(1),
            "bestDiff": .string("500"),
            "networkDifficulty": .string("100"),
            "uptimeSeconds": .integer(120)
        ])
        // Counter dropped then, on a later poll, climbed again after the reboot baseline.
        let reclimb = MinerInfo(raw: [
            "blockFound": .integer(2),
            "bestDiff": .string("500"),
            "networkDifficulty": .string("100"),
            "uptimeSeconds": .integer(150)
        ])
        #expect(
            MinerBlockFoundEvent.detect(device: device, previous: before, current: afterReboot, occurredAt: Date())
                == nil
        )
        // Even a normal increase is honored here (no reboot between these two, share meets target).
        #expect(
            MinerBlockFoundEvent.detect(device: device, previous: afterReboot, current: reclimb, occurredAt: Date())
                != nil
        )
    }

    @Test func counterIncreaseBelowNetworkTargetStillFiresWhenNotRebooted() {
        let device = MinerDevice(name: "Gamma", address: "http://192.168.1.60")
        // The firmware only raises blockFound when it believes it solved a block. Detection must
        // not silently drop that claim just because bestDiff is below the reported networkDifficulty
        // (a value the firmware may omit or report inconsistently). The reboot guard is what stops
        // phantoms, not a best-share-versus-target proof.
        let baseline = MinerInfo(raw: [
            "blockFound": .integer(0),
            "bestDiff": .string("433790793"),
            "networkDifficulty": .string("127450789715843"),
            "uptimeSeconds": .integer(1_000)
        ])
        let increased = MinerInfo(raw: [
            "blockFound": .integer(1),
            "bestDiff": .string("433790793"),
            "networkDifficulty": .string("127450789715843"),
            "uptimeSeconds": .integer(1_030)
        ])
        #expect(
            MinerBlockFoundEvent.detect(device: device, previous: baseline, current: increased, occurredAt: Date())
                != nil
        )
    }

    @Test func blockFlagTransitionIsSeparateFromAImprovedDifficultyShare() {
        let device = MinerDevice(name: "Gamma", address: "http://192.168.1.60")
        let oldShare = MinerInfo(raw: ["bestDiff": .string("10"), "showNewBlock": .bool(false)])
        let betterShare = MinerInfo(raw: ["bestDiff": .string("20"), "showNewBlock": .bool(false)])
        let blockFlag = MinerInfo(raw: ["bestDiff": .string("20"), "showNewBlock": .bool(true)])

        #expect(
            MinerBlockFoundEvent.detect(device: device, previous: oldShare, current: betterShare, occurredAt: Date())
                == nil
        )
        #expect(
            MinerBlockFoundEvent.detect(device: device, previous: betterShare, current: blockFlag, occurredAt: Date())
                != nil
        )
    }

    @Test func blockNotificationContentUsesOnlySafeMinerContext() {
        let event = MinerBlockFoundEvent(
            id: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
            deviceID: UUID(uuidString: "55555555-5555-4555-8555-555555555555")!,
            minerName: "Gamma 601",
            coinLabel: "BTC",
            height: 900_001,
            count: 2,
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let content = FleetBlockNotificationContent(event: event)

        #expect(content.identifier == "app.hashfleet.block-found.44444444-4444-4444-8444-444444444444")
        #expect(content.title == "Block found by Gamma 601")
        #expect(content.body == "BTC · The miner explicitly reported a found block at height 900001.")
        #expect(!content.body.contains("192.168"))
        #expect(!content.body.contains("stratum"))
        #expect(!content.body.contains("wallet"))
    }

    // MARK: - MinerMiningContext Tests

    @Test func miningContextUsesTheExplicitActivePoolAndSafeLabels() {
        let info = MinerInfo(raw: [
            "isUsingFallbackStratum": .integer(0),
            "primaryPoolIndex": .integer(0),
            "secondaryPoolIndex": .integer(1),
            "pools": .array([
                .object([
                    "id": .integer(0),
                    "stratumURL": .string("stratum.ckpool.org"),
                    "stratumUser": .string("wallet.worker")
                ]),
                .object([
                    "id": .integer(1),
                    "stratumURL": .string("bch.solofury.com"),
                    "stratumUser": .string("cash.worker")
                ])
            ])
        ])

        let context = MinerMiningContext.resolve(info: info)

        #expect(context.headline == "BTC · CKPool")
        #expect(context.routeLabel == "Active · Primary")
        #expect(context.sourceLabel == "Miner reported")
        #expect(context.symbol == "server.rack")
    }

    @Test func miningContextDoesNotInventPoolOrCoinWhenFirmwareOmitsSetup() {
        let context = MinerMiningContext.resolve(
            info: MinerInfo(raw: [
                "hostname": .string("miner-without-pool")
            ])
        )

        #expect(context.headline == "Pool not reported")
        #expect(context.routeLabel == "Awaiting miner reading")
        #expect(context.sourceLabel == "Not reported")
    }

    // MARK: - MinerActivePool Tests

    @Test func activePoolReportsPrimaryWhenFallbackIsExplicitlyFalse() {
        let info = MinerInfo(raw: [
            "isUsingFallbackStratum": .integer(0),
            "stratumURL": .string("stratum+tcp://pool.primary.com:3333"),
            "fallbackStratumURL": .string("stratum+tcp://pool.fallback.com:3333")
        ])
        let pool = MinerActivePool(info: info)
        #expect(pool.title == "Pool · primary")
        #expect(pool.value == "stratum+tcp://pool.primary.com:3333")
        #expect(pool.isUsingFallback == false)
    }

    @Test func activePoolReportsFallbackWhenFallbackIsExplicitlyTrue() {
        let info = MinerInfo(raw: [
            "isUsingFallbackStratum": .integer(1),
            "stratumURL": .string("stratum+tcp://pool.primary.com:3333"),
            "fallbackStratumURL": .string("stratum+tcp://pool.fallback.com:3333")
        ])
        let pool = MinerActivePool(info: info)
        #expect(pool.title == "Pool · fallback in use")
        #expect(pool.value == "stratum+tcp://pool.fallback.com:3333")
        #expect(pool.isUsingFallback == true)
    }

    @Test func activePoolFallbackMissingURLNeverFallsBackToPrimaryURL() {
        // When fallback is true, but fallbackStratumURL is missing or empty,
        // it must NEVER fall back to primary stratumURL!
        let info = MinerInfo(raw: [
            "isUsingFallbackStratum": .bool(true),
            "stratumURL": .string("stratum+tcp://pool.primary.com:3333"),
            "fallbackStratumURL": .null
        ])
        let pool = MinerActivePool(info: info)
        #expect(pool.title == "Pool · fallback in use")
        #expect(pool.value == "Not reported")
        #expect(pool.isUsingFallback == true)
    }

    @Test func activePoolFallbackWithEmptyStringURLShowsNotReported() {
        let info = MinerInfo(raw: [
            "isUsingFallbackStratum": .string("1"),
            "stratumURL": .string("stratum+tcp://pool.primary.com:3333"),
            "fallbackStratumURL": .string("   \n")
        ])
        let pool = MinerActivePool(info: info)
        #expect(pool.title == "Pool · fallback in use")
        #expect(pool.value == "Not reported")
        #expect(pool.isUsingFallback == true)
    }

    @Test func activePoolAbsentFallbackFlagLabelsConfiguredPrimaryWithoutClaimingActiveConnection() {
        // When isUsingFallbackStratum is missing, we must NOT claim primary is active/connected.
        let info = MinerInfo(raw: [
            "stratumURL": .string("stratum+tcp://pool.primary.com:3333")
        ])
        let pool = MinerActivePool(info: info)
        #expect(pool.title == "Pool · configured primary")
        #expect(pool.value == "stratum+tcp://pool.primary.com:3333")
        #expect(pool.isUsingFallback == false)
    }

    @Test func activePoolSupportsLegacyPoolURLKey() {
        let info = MinerInfo(raw: [
            "isUsingFallbackStratum": .bool(false),
            "poolURL": .string("stratum+tcp://legacy.pool.com:4444")
        ])
        let pool = MinerActivePool(info: info)
        #expect(pool.title == "Pool · primary")
        #expect(pool.value == "stratum+tcp://legacy.pool.com:4444")
        #expect(pool.isUsingFallback == false)
    }

    @Test func activePoolAllFieldsAbsentShowsNotReported() {
        let info = MinerInfo(raw: [:])
        let pool = MinerActivePool(info: info)
        #expect(pool.title == "Pool · configured primary")
        #expect(pool.value == "Not reported")
        #expect(pool.isUsingFallback == false)
    }

    @Test func activePoolHandlesMalformedBooleanFallbackFlag() {
        // "garbage" does not convert to boolean; fallbackFlag is nil -> absent flag behavior
        let info = MinerInfo(raw: [
            "isUsingFallbackStratum": .string("unknown_flag"),
            "stratumURL": .string("stratum+tcp://pool.com:3333")
        ])
        let pool = MinerActivePool(info: info)
        #expect(pool.title == "Pool · configured primary")
        #expect(pool.value == "stratum+tcp://pool.com:3333")
        #expect(pool.isUsingFallback == false)
    }

}
