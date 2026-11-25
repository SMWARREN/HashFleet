import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

/// The app speaks one HTTP API across several hardware families, but they do not share a release
/// feed. Offering a NerdQAxe owner a Bitaxe build is wrong, so identification must be evidence-based.
@Suite("Firmware family identification")
struct MinerFirmwareFamilyTests {
    private func info(_ pairs: [String: String]) -> MinerInfo {
        MinerInfo(raw: pairs.mapValues { JSONValue.string($0) })
    }

    @Test func boardVersionIdentifiesBitaxe() {
        #expect(MinerFirmwareFamily.identify(from: info(["boardVersion": "Bitaxe Ultra 204"])) == .bitaxe)
    }

    @Test func nerdqaxeIsNotMisreadAsBitaxeDespiteContainingAxe() {
        // "nerdqaxe" contains "axe"; a naive substring check would mis-route the release feed.
        for value in ["NerdQAxe++", "nerdqaxeplus", "NerdOCTAXE-Gamma"] {
            #expect(
                MinerFirmwareFamily.identify(from: info(["boardVersion": value])) == .nerdqaxe,
                "\(value) must resolve to the NerdQAxe project"
            )
        }
    }

    @Test func hostnameAndDeviceModelAreAlsoAcceptedAsEvidence() {
        #expect(MinerFirmwareFamily.identify(from: info(["hostname": "nerdqaxe-a1b2"])) == .nerdqaxe)
        #expect(MinerFirmwareFamily.identify(from: info(["deviceModel": "Bitaxe Gamma"])) == .bitaxe)
    }

    @Test func unknownHardwareYieldsNoFamilyRatherThanAGuess() {
        #expect(MinerFirmwareFamily.identify(from: info(["hostname": "miner-01"])) == nil)
        #expect(MinerFirmwareFamily.identify(from: info([:])) == nil)
        #expect(MinerFirmwareFamily.identify(from: nil) == nil)
        // Blank strings are absence of evidence, not evidence.
        #expect(MinerFirmwareFamily.identify(from: info(["boardVersion": "   "])) == nil)
    }

    @Test func eachFamilyPointsAtItsOwnProjectFeed() {
        let bitaxe = MinerFirmwareFamily.bitaxe.releaseFeedURL.absoluteString
        let nerdqaxe = MinerFirmwareFamily.nerdqaxe.releaseFeedURL.absoluteString
        #expect(bitaxe.contains("bitaxeorg/ESP-Miner"))
        #expect(nerdqaxe.contains("NerdQAxePlus"))
        #expect(bitaxe != nerdqaxe)
        for url in [bitaxe, nerdqaxe] {
            #expect(url.hasPrefix("https://"))
        }
    }

    @Test func everyFamilyHasADistinctDisplayNameAndFeed() {
        let names = Set(MinerFirmwareFamily.allCases.map(\.displayName))
        let feeds = Set(MinerFirmwareFamily.allCases.map(\.releaseFeedURL))
        #expect(names.count == MinerFirmwareFamily.allCases.count)
        #expect(feeds.count == MinerFirmwareFamily.allCases.count)
    }
}

/// Each family's live-socket capability comes from its pinned upstream registrar. Only ESP-Miner
/// registers `/api/ws/live`; NerdQAxe and Bitfortun register only the `/api/ws` log stream.
@Suite("Firmware live-socket capability")
struct MinerFirmwareLiveSocketTests {
    @Test func onlyESPMinerRegistersTheLiveSocket() {
        #expect(MinerFirmwareFamily.bitaxe.supportsLiveWebSocket)
        #expect(!MinerFirmwareFamily.nerdqaxe.supportsLiveWebSocket)
        #expect(!MinerFirmwareFamily.bitfortun.supportsLiveWebSocket)
        #expect(!MinerFirmwareFamily.axeForge.supportsLiveWebSocket)
    }

    @Test func bitfortunBoardStringsResolveToBitfortunNotBitaxe() {
        // Upstream bitfortun-BS-1 sets deviceModel to BitfortunAxe, BitfortunQAxe+, BitfortunOCTAXE+ etc.
        for value in ["BitfortunAxe", "BitfortunQAxe+", "BitfortunOCTAXE+", "BitfortunEKO", "BitfortunAxeGamma"] {
            #expect(
                MinerFirmwareFamily.identify(from: MinerInfo(raw: ["deviceModel": .string(value)])) == .bitfortun,
                "\(value) must resolve to Bitfortun"
            )
        }
    }

    @Test func axeForgeBoardNamesResolveToAxeForge() {
        // Upstream AxeForge names its board from boards/*.toml, e.g. "Bitfortun BS-1" in bs1.toml.
        // That name also contains "Bitfortun", so AxeForge must be checked before Bitfortun.
        let forged = MinerFirmwareFamily.identify(from: MinerInfo(raw: ["board": .string("AxeForge rev5.1/6")]))
        #expect(forged == .axeForge)
    }

    @Test func fleetBoardsStayOnESPMinerAndKeepTheSocket() {
        // Gamma 602, Gamma 601a and both Naja Duos report ESP-Miner identity: no project string.
        for board in ["602", "601a", "1201"] {
            let info = MinerInfo(raw: ["boardVersion": .string(board), "axeOSVersion": .string("Unified"),
                                       "hostname": .string("bitaxe")])
            #expect(MinerFirmwareFamily.identify(from: info) == .bitaxe, "board \(board) must stay ESP-Miner")
        }
    }
}

@Suite("Saved firmware family")
struct MinerSavedFirmwareFamilyTests {
    @Test func olderSavedDevicesDecodeWithoutAFamily() throws {
        let legacy = Data(#"{"id":"\#(UUID().uuidString)","name":"Desk","address":"192.168.1.10","kind":"espMiner"}"#.utf8)
        let device = try JSONDecoder().decode(MinerDevice.self, from: legacy)
        #expect(device.firmwareFamily == nil)
    }

    @Test func familyRoundTripsThroughTheSavedFleet() throws {
        let device = MinerDevice(name: "Naja", address: "192.168.86.239", firmwareFamily: "bitaxe")
        let decoded = try JSONDecoder().decode(MinerDevice.self, from: JSONEncoder().encode(device))
        #expect(decoded.firmwareFamily == "bitaxe")
    }

    @Test func discoveryCandidateSupportsNestedNmaxeAndAxeForgeStatusPayloads() {
        let nmaxeBody = Data(#"""
        {
          "miner":{"hashRate":1200,"uptimeSeconds":500,"sAccepted":10,"sRejected":0},
          "identity":{"hwModel":"NMAxeGamma","hostName":"nmaxe-gamma","fwVersion":"v3.0.21"},
          "asic":{"model":"BM1370","freqReq":525}
        }
        """#.utf8)
        let nmaxeCandidate = MinerDiscoveryService.candidate(
            host: "192.168.1.70",
            statusCode: 200,
            contentType: "application/json",
            body: nmaxeBody
        )
        #expect(nmaxeCandidate?.name == "nmaxe-gamma")
        #expect(nmaxeCandidate?.model == "BM1370")

        let axeForgeBody = Data(#"""
        {
          "status":"mining",
          "hashrate":4850,
          "chipTemp":57.5,
          "board":"AxeForge rev5.1/6",
          "asicModel":"BM1370",
          "hostname":"axeforge-rack",
          "version":"v1.4.2",
          "pool":{"connected":true,"host":"solo.ckpool.org:3333","accepted":20,"rejected":0}
        }
        """#.utf8)
        let axeForgeCandidate = MinerDiscoveryService.candidate(
            host: "192.168.1.71",
            statusCode: 200,
            contentType: "application/json",
            body: axeForgeBody
        )
        #expect(axeForgeCandidate?.name == "axeforge-rack")
        #expect(axeForgeCandidate?.model == "BM1370")
        #expect(axeForgeCandidate?.firmwareFamily == .axeForge)
        #expect(axeForgeCandidate?.detectedFamily == "axeForge")
        #expect(nmaxeCandidate?.detectedFamily == "nmaxe")
    }

    @Test func discoveryScanFollows404ToAxeForgeAndHarloOSEndpoints() async throws {
        let plan = MinerDiscoveryScanPlan(localAddress: "192.168.1.2", hosts: ["192.168.1.60", "192.168.1.80"])
        let found = try await MinerDiscoveryService.scan(plan: plan, transport: { req in
            let host = req.url?.host ?? ""
            let path = req.url?.path ?? ""
            let ok = HTTPURLResponse(
                url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            let notFound = HTTPURLResponse(
                url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            if host == "192.168.1.60" && path == "/api/status" {
                let body = Data(#"""
                {
                  "status":"mining","hashrate":4850,"chipTemp":57.5,
                  "board":"AxeForge rev5.1/6","asicModel":"BM1370",
                  "hostname":"axeforge-rack","version":"v1.4.2",
                  "pool":{"connected":true,"host":"solo.ckpool.org:3333","accepted":20,"rejected":0}
                }
                """#.utf8)
                return (body, ok)
            }
            if host == "192.168.1.80" && path == "/api/telemetry" {
                let body = Data(#"""
                {"miner_name":"harlo-b30","firmware_version":"0.2.101","hashrate_ghs":30000,"device_power_w":430,"asic_temp_c":58,"target_frequency_mhz":600,"target_core_mv":1200}
                """#.utf8)
                return (body, ok)
            }
            return (Data(), notFound)
        })
        #expect(found.count == 2)
        #expect(found[0].name == "axeforge-rack" && found[0].detectedFamily == "axeForge")
        #expect(found[1].name == "harlo-b30" && found[1].detectedFamily == "harloOS")
    }

    @Test func nerdqaxeForkTelemetryIdentifiesNerdQAxeWhenStringsOmitProjectName() {
        let dualFan = MinerInfo(raw: ["hostname": .string("miner-02"), "fanCount": .integer(2)])
        #expect(MinerFirmwareFamily.identify(from: dualFan) == .nerdqaxe)

        let psuCurrent = MinerInfo(raw: ["hostname": .string("miner-03"), "currentA": .number(7.5)])
        #expect(MinerFirmwareFamily.identify(from: psuCurrent) == .nerdqaxe)
    }

    @MainActor
    @Test func fleetStorePicksUpAndRefinesDeviceFirmwareFamilyFromTelemetryAndASIC() throws {
        let defaults = UserDefaults(suiteName: "test.family.pickup.\(UUID().uuidString)")!
        let store = FleetStore(defaults: defaults, session: .shared)
        try store.add(name: "Manual Miner", address: "192.168.1.90")
        let id = try #require(store.devices.first?.id)
        #expect(store.devices.first?.firmwareFamily == nil)

        // 1. Initial Bitaxe telemetry sets family to "bitaxe"
        let bitaxeInfo = MinerInfo(raw: [
            "hostname": .string("bitaxe-01"),
            "boardVersion": .string("602"),
            "hashRate": .number(1200)
        ])
        #expect(store.updateDetectedFirmwareFamily(for: id, info: bitaxeInfo))
        #expect(store.devices.first?.firmwareFamily == "bitaxe")

        // 2. Subsequent /api/system/asic check revealing BITFORGE_NANO upgrades family to "bitforge"
        let asicPayload: JSONValue = .object(["deviceModel": .string("BITFORGE_NANO")])
        #expect(store.updateDetectedFirmwareFamily(for: id, info: bitaxeInfo, asic: asicPayload))
        #expect(store.devices.first?.firmwareFamily == "bitforge")
    }

    @MainActor
    @Test func minerAvailabilityEnablesAndDisablesControlsPerFirmwareCapabilities() throws {
        let defaults = UserDefaults(suiteName: "test.family.caps.\(UUID().uuidString)")!
        let store = FleetStore(defaults: defaults, session: .shared)

        func checkFamily(
            _ family: String,
            raw: [String: JSONValue]
        ) throws -> MinerNumberFirstAvailability {
            let addr = "192.168.1.\(store.devices.count + 10)"
            let dev = MinerDevice(name: family, address: addr, firmwareFamily: family)
            store.devices.append(dev)
            let info = MinerInfo(raw: raw)
            store.snapshots[dev.id] = MinerSnapshot(info: info, updatedAt: .now, completeSnapshotAt: .now)
            return NumberFirstPreview.minerAvailability(info, device: dev, store: store)
        }

        // 1. NMAxe (MAC-less): Cooling & Restart enabled; Tuning, Pools, Identify, Pause, Resume disabled
        let nmaxeAvail = try checkFamily("nmaxe", raw: [
            "firmwareFamily": .string("nmaxe"),
            "hostname": .string("nm-qaxe"),
            "version": .string("v3.0.21"),
            "hashRate": .number(2400),
            "frequency": .number(550),
            "coreVoltage": .number(1200),
            "autofanspeed": .integer(0),
            "manualFanSpeed": .integer(65),
            "stratumURL": .string("solo.ckpool.org")
        ])
        #expect(nmaxeAvail.cooling)
        #expect(!nmaxeAvail.tuning)
        #expect(!nmaxeAvail.settingsCategories(usesEssentialsPools: true).contains(.pools))
        #expect(nmaxeAvail.quickActions == [.restart])

        // 2. AxeForge (MAC-less): Cooling, Tuning, Pools, Identify & Restart enabled; Pause/Resume disabled
        let axeForgeAvail = try checkFamily("axeForge", raw: [
            "firmwareFamily": .string("axeForge"),
            "hostname": .string("axeforge-nq"),
            "board": .string("AxeForge rev5.1/6"),
            "version": .string("v1.4.2"),
            "hashRate": .number(4900),
            "frequency": .number(600),
            "coreVoltage": .number(1180),
            "autofanspeed": .integer(0),
            "manualFanSpeed": .integer(65),
            "stratumURL": .string("solo.ckpool.org")
        ])
        #expect(axeForgeAvail.cooling && axeForgeAvail.tuning)
        #expect(axeForgeAvail.settingsCategories(usesEssentialsPools: true).contains(.pools))
        #expect(axeForgeAvail.quickActions == [.identify, .restart])

        // 3. Harlo-OS: Cooling, Tuning, Pools, Pause, Resume & Restart enabled; Identify disabled
        let harloAvail = try checkFamily("harloOS", raw: [
            "firmwareFamily": .string("harloOS"),
            "hostname": .string("harlo-b30"),
            "macAddr": .string("02:11:22:33:44:55"),
            "version": .string("0.2.101"),
            "hashRate": .number(30000),
            "frequency": .number(600),
            "coreVoltage": .number(1210),
            "autofanspeed": .integer(1),
            "temptarget": .integer(58),
            "stratumURL": .string("us-east.harlolabs.com")
        ])
        #expect(harloAvail.cooling && harloAvail.tuning)
        #expect(harloAvail.settingsCategories(usesEssentialsPools: true).contains(.pools))
        #expect(harloAvail.quickActions == [.pause, .resume, .restart])

        // 4. LuxOS / Braiins: Read-only (all write controls & quick actions disabled)
        let luxAvail = try checkFamily("luxos", raw: [
            "firmwareFamily": .string("luxos"),
            "hostname": .string("antminer-s21"),
            "macAddr": .string("AA:BB:CC:DD:EE:FF"),
            "version": .string("0.1.0"),
            "hashRate": .number(195000),
            "frequency": .number(600),
            "coreVoltage": .number(1250),
            "autofanspeed": .integer(0),
            "manualFanSpeed": .integer(80)
        ])
        #expect(!luxAvail.canEditSettings)
        #expect(!luxAvail.cooling && !luxAvail.tuning)
        #expect(luxAvail.quickActions.isEmpty)
    }
}

@Suite("ThorOS firmware family")
struct MinerThorOSFirmwareFamilyTests {
    @Test func thorBoardsUseTheirOwnHammerFeed() {
        let x1 = MinerInfo(raw: ["device_model": .string("THOR X1"), "firmware_version": .string("1.0.6")])
        let p2 = MinerInfo(raw: ["device_model": .string("THOR P2"), "firmware_version": .string("1.1.0")])
        let bc08 = MinerInfo(raw: ["device_model": .string("THOR BC08"), "firmware_version": .string("1.1.1")])
        #expect(MinerFirmwareFamily.identify(from: x1) == .thorX1)
        #expect(MinerFirmwareFamily.identify(from: p2) == .thorP2)
        #expect(MinerFirmwareFamily.identify(from: bc08) == nil)
        #expect(MinerFirmwareFamily.thorX1.releaseFeedURL.absoluteString.contains("HammerMiner/X1"))
        #expect(MinerFirmwareFamily.thorP2.releaseFeedURL.absoluteString.contains("HammerMiner/P2"))
        #expect(!MinerFirmwareFamily.thorP2.supportsLiveWebSocket)
    }
}
