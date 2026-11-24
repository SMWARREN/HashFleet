import Foundation
import Testing
@testable import HashFleetCore

@Suite("MinerWatch & AxeForge drivers and detection order")
struct MinerFirmwareAdapterTests {

    // MARK: - Detection Order Tests

    @Test("1. NMAxe is detected first via GET /probe even if model contains QAxe")
    func detectsNmaxeFirstViaProbe() async {
        // NMQAxe++ has "qaxe" in its name, which would trip the NerdQAxe heuristic if NMAxe didn't run first.
        let identity = await MinerFirmwareAdapter.identifyHost(
            "192.168.1.50",
            httpTransport: { req in
                let path = req.url?.path ?? ""
                if path == "/probe" {
                    let body = Data(#"{"model":"NMQAxe++","hostname":"nm-qaxe-01","version":"v3.0.21"}"#.utf8)
                    return (body, Self.httpResponse(url: req.url!))
                }
                if path == "/api/system/info" {
                    let body = Data(#"""
                    {
                      "miner":{"hashRate":2450.0,"uptimeSeconds":3600,"sAccepted":42,"sRejected":1,"bestDiffSession":"1.2G","bestDiffEver":"4.5G","paused":false},
                      "power":{"power":38.5,"vbus":12100,"ibus":3180},
                      "temps":{"asic":56.2,"vcore":61.0},
                      "asic":{"model":"BM1366","freqReq":550,"vcoreReal":1200,"vcoreReq":1210,"count":4,"smallCoreCnt":894},
                      "identity":{"hwModel":"NMQAxe++","hostName":"nm-qaxe-01","fwVersion":"v3.0.21"},
                      "stratum":{"url":"stratum+tcp://solo.ckpool.org:3333","user":"bc1qtest.nm1"},
                      "fans":[{"rpm":4200,"speed":65},{"rpm":3800,"speed":55}]
                    }
                    """#.utf8)
                    return (body, Self.httpResponse(url: req.url!))
                }
                throw URLError(.fileDoesNotExist)
            }
        )
        #expect(identity?.family == "nmaxe")
        #expect(identity?.model == "NMQAxe++")
        #expect(identity?.name == "nm-qaxe-01")
        #expect(identity?.mac == nil)
        #expect(identity?.info.hashRate == 2450.0)
        #expect(identity?.info.power == 38.5)
        #expect(identity?.info.temp == 56.2)
        #expect(identity?.info.vrTemp == 61.0)
        #expect(identity?.info.fanRpm == 4200)
        #expect(identity?.info.fan2Rpm == 3800)
        #expect(identity?.info.sharesAccepted == 42)
        #expect(identity?.info.poolURL == "solo.ckpool.org")
    }

    @Test("2. BitForge is detected via deviceModel or chiptemp1 before NerdQAxe")
    func detectsBitForgeViaDeviceModelOrChipTemp1() async {
        // Test A: via /api/system/asic deviceModel "BITFORGE_NANO" even when fanCount > 1
        let viaDeviceModel = await MinerFirmwareAdapter.identifyHost(
            "192.168.1.51",
            httpTransport: { req in
                let path = req.url?.path ?? ""
                if path == "/api/system/info" {
                    let body = Data(#"""
                    {
                      "hostname":"forge-nano","ASICModel":"BM1370","asicCount":2,
                      "hashRate":2300,"power":34.2,"temp":57.0,"chiptemp1":55.0,"chiptemp2":59.0,
                      "fanSpeed":70,"fanrpm":4500,"current":2850,"fanCount":2
                    }
                    """#.utf8)
                    return (body, Self.httpResponse(url: req.url!))
                }
                if path == "/api/system/asic" {
                    let body = Data(#"{"deviceModel":"BITFORGE_NANO","asicCount":2}"#.utf8)
                    return (body, Self.httpResponse(url: req.url!))
                }
                return (Data(), Self.httpResponse(url: req.url!, status: 404))
            }
        )
        #expect(viaDeviceModel?.family == "bitforge")
        #expect(viaDeviceModel?.model == "BitForge Nano")
        // BitForge temp_chip_c must be max(chiptemp1, chiptemp2) = 59.0, not the average 57.0
        #expect(viaDeviceModel?.info.temp == 59.0)
        #expect(viaDeviceModel?.info.temp2 == 59.0)
        #expect(viaDeviceModel?.info.raw["tempAvg"]?.doubleValue == 57.0)
        #expect(viaDeviceModel?.info.fanSpeed == 70.0)
        #expect(viaDeviceModel?.info.raw["currentA"]?.doubleValue == 2.85)

        // Test B: forge-os v1.0 without /api/system/asic (or deviceModel="invalid"), detected via chiptemp1
        let viaChipTemp1 = await MinerFirmwareAdapter.identifyHost(
            "192.168.1.52",
            httpTransport: { req in
                let path = req.url?.path ?? ""
                if path == "/api/system/info" {
                    let body = Data(#"""
                    {"hostname":"nano-v1","ASICModel":"BM1370","asicCount":2,"hashRate":2150,"power":32.0,"temp":54.0,"chiptemp1":52.0,"chiptemp2":56.0,"fanspeed":60,"fanrpm":4100}
                    """#.utf8)
                    return (body, Self.httpResponse(url: req.url!))
                }
                if path == "/api/system/asic" {
                    let body = Data(#"{"deviceModel":"invalid"}"#.utf8)
                    return (body, Self.httpResponse(url: req.url!))
                }
                return (Data(), Self.httpResponse(url: req.url!, status: 404))
            }
        )
        #expect(viaChipTemp1?.family == "bitforge")
        #expect(viaChipTemp1?.model == "BitForge Nano")
        #expect(viaChipTemp1?.info.temp == 56.0)
    }

    @Test("3. NerdQAxe is detected via deviceModel, fanCount > 1, or currentA")
    func detectsNerdQAxeViaModelFanCountOrCurrentA() {
        // Via deviceModel
        #expect(
            MinerFirmwareAdapter.classifyAxeOSPayload(
                raw: ["hashRate": .number(4800)],
                asic: ["deviceModel": .string("NerdOCTAXE-Gamma")]
            ) == "nerdqaxe"
        )
        // Via fanCount > 1
        #expect(
            MinerFirmwareAdapter.classifyAxeOSPayload(
                raw: ["hashRate": .number(4800), "fanCount": .integer(2)]
            ) == "nerdqaxe"
        )
        // Via currentA
        #expect(
            MinerFirmwareAdapter.classifyAxeOSPayload(
                raw: ["hashRate": .number(4800), "currentA": .number(8.4)]
            ) == "nerdqaxe"
        )
        // fallbackStratumURL alone must NOT misclassify a standard Bitaxe as NerdQAxe
        #expect(
            MinerFirmwareAdapter.classifyAxeOSPayload(
                raw: [
                    "hashRate": .number(1200),
                    "ASICModel": .string("BM1370"),
                    "fallbackStratumURL": .string("solo.ckpool.org")
                ]
            ) == "bitaxe"
        )
    }

    @Test("4. Bitaxe is detected otherwise and applies plausibility clamp & hottest sensor")
    func bitaxeDriverParsingAndSanityClamp() {
        // Normal multi-sensor SupraHex reading: temp2 (64°C) is hotter than temp (52°C)
        let normal = MinerHTTPDrivers.parseBitaxe(data: [
            "hostname": .string("suprahex"),
            "ASICModel": .string("BM1368"),
            "hashRate": .number(4200),
            "power": .number(72.0),
            "temp": .number(52.0),
            "temp2": .number(64.0),
            "vrTemp": .number(68.0),
            "frequency": .number(500),
            "smallCoreCount": .integer(1276),
            "asicCount": .integer(6),
            "sharesAccepted": .integer(100),
            "sharesRejected": .integer(2),
            "bestDiff": .string("4.29G"),
            "bestSessionDiff": .string("512M")
        ])
        #expect(normal.family == "bitaxe")
        #expect(normal.hashrateTHs == 4.2)
        #expect(normal.tempChipC == 64.0)
        #expect(normal.tempChip2C == 64.0)
        #expect(normal.bestDifficulty == 512_000_000)
        #expect(normal.bestDifficultyAllTime == 4_290_000_000)

        // Spurious transient spike after ASIC resume (9.5e8 GH/s >> 3x theoretical max)
        let spiked = MinerHTTPDrivers.parseBitaxe(data: [
            "hashRate": .number(950_000_000),
            "frequency": .number(500),
            "smallCoreCount": .integer(2040),
            "asicCount": .integer(1),
            "power": .number(18.0)
        ])
        #expect(spiked.hashrateTHs == nil)
        let spikedInfo = spiked.toMinerInfo(preservingFlatRaw: true)
        #expect(spikedInfo.raw["hashRate"] == nil)
    }

    @Test("5. Port 4028 cgminer fingerprints LuxOS, then Braiins, otherwise Canaan by version keys")
    func cgminerFingerprintAndDrivers() async throws {
        // 1. LuxOS fingerprint (LUXminer key)
        let luxVersion: [String: JSONValue] = [
            "VERSION": .array([.object([
                "LUXminer": .string("0.1.0-15436f"),
                "API": .string("3.7"),
                "PROD": .string("Antminer S21"),
                "MAC": .string("aa-bb-cc-dd-ee-ff")
            ])])
        ]
        #expect(MinerCgminerDrivers.fingerprint(versionResponse: luxVersion) == "luxos")
        let luxSample = MinerCgminerDrivers.parseLuxos(
            version: luxVersion,
            summary: [
                "SUMMARY": .array([.object([
                    "GHS 1m": .number(195_000),
                    "Accepted": .integer(500),
                    "Rejected": .integer(3),
                    "Elapsed": .integer(7200),
                    "Best Share": .string("12.5G")
                ])])
            ],
            devs: [
                "DEVS": .array([.object([
                    "ID": .integer(0),
                    "Temperature": .number(63.5),
                    "Frequency": .number(600),
                    "Hardware Errors": .integer(10),
                    "Diff1 Work": .integer(990)
                ])])
            ],
            power: ["POWER": .array([.object(["Watts": .number(3450)])])],
            pools: [
                "POOLS": .array([.object([
                    "URL": .string("stratum+tcp://btc.luxor.tech:700"),
                    "User": .string("worker1"),
                    "Status": .string("Alive"),
                    "Stratum Active": .bool(true),
                    "Priority": .integer(0)
                ])])
            ]
        )
        #expect(luxSample.family == "luxos")
        #expect(luxSample.chipModel == "BM1370")
        #expect(luxSample.mac == "AA:BB:CC:DD:EE:FF")
        #expect(luxSample.hashrateTHs == 195.0)
        #expect(luxSample.powerW == 3450.0)
        #expect(luxSample.tempChipC == 63.5)
        #expect(luxSample.hwErrorRate == 1.0)
        let luxInfo = luxSample.toMinerInfo()
        #expect(luxInfo.hashRate == 195_000.0)
        #expect(luxInfo.macAddress == "AABBCCDDEEFF")
    }

    @Test("5b. Port 4028 cgminer fingerprints Braiins and Canaan Avalon")
    func cgminerBraiinsAndCanaanDrivers() {
        // 2. Braiins fingerprint (BOSminer / BOSminer+ key)
        let bosVersion: [String: JSONValue] = [
            "VERSION": .array([.object([
                "BOSminer+": .string("23.08"),
                "API": .string("3.7")
            ])])
        ]
        #expect(MinerCgminerDrivers.fingerprint(versionResponse: bosVersion) == "braiins")
        let bosSample = MinerCgminerDrivers.parseBraiins(
            version: bosVersion,
            summary: ["SUMMARY": .array([.object(["GHS 1m": .number(1050), "Accepted": .integer(88), "Rejected": .integer(0), "Elapsed": .integer(1800)])])],
            temps: ["TEMPS": .array([.object(["ID": .integer(1), "Chip": .number(61.5), "Board": .number(54.0)])])],
            fans: ["FANS": .array([.object(["ID": .integer(0), "RPM": .integer(3400), "Speed": .number(70)])])],
            tunerstatus: ["TUNERSTATUS": .array([.object(["ApproximateMinerPowerConsumption": .number(36.4)])])]
        )
        #expect(bosSample.family == "braiins")
        #expect(bosSample.hashrateTHs == 1.05)
        #expect(bosSample.tempChipC == 61.5)
        #expect(bosSample.tempVRC == 54.0)
        #expect(bosSample.fanRPM == 3400)
        #expect(bosSample.powerW == 36.4)

        // 3. Canaan Avalon fallback fingerprint (neither LUX nor BOS keys)
        let canaanVersion: [String: JSONValue] = [
            "VERSION": .array([.object([
                "CGMiner": .string("4.11.1"),
                "PROD": .string("Avalon Nano3s"),
                "MAC": .string("0201a8c8e798")
            ])])
        ]
        #expect(MinerCgminerDrivers.fingerprint(versionResponse: canaanVersion) == "canaan")
        let mmID0 = "Ver[Nano3s-25021401] Elapsed[177873] ITemp[-273] OTemp[34] TMax[66] TAvg[61] "
            + "Fan1[2600] FanR[55%] GHSavg[6227.17] Freq[432.25] MPO[133] PVT_V0[321 313 316] WORKMODE[2] PING[33]"
        let canaanSample = MinerCgminerDrivers.parseCanaan(
            version: canaanVersion,
            summary: [
                "SUMMARY": .array([.object([
                    "MHS 5m": .number(6_200_000),
                    "Accepted": .integer(310),
                    "Rejected": .integer(1),
                    "Elapsed": .integer(177873),
                    "Best Share": .integer(84000)
                ])])
            ],
            stats: ["STATS": .array([.object(["MM ID0": .string(mmID0)])])],
            pools: [
                "POOLS": .array([.object([
                    "URL": .string("stratum+tcp://solo.ckpool.org:3333"),
                    "User": .string("bc1qavalon"),
                    "Status": .string("Alive"),
                    "Stratum Active": .string("true"),
                    "Priority": .integer(0)
                ])])
            ]
        )
        #expect(canaanSample.family == "canaan")
        #expect(canaanSample.model == "Avalon Nano3s")
        #expect(canaanSample.mac == "02:01:A8:C8:E7:98")
        #expect(canaanSample.hashrateTHs == 6.2)
        #expect(canaanSample.tempChipC == 66.0)
        #expect(canaanSample.tempVRC == 34.0)
        #expect(canaanSample.tempInletC == nil) // -273 sentinel dropped
        #expect(canaanSample.fanRPM == 2600)
        #expect(canaanSample.fanPct == 55.0)
        #expect(canaanSample.powerW == 133.0)
        #expect(canaanSample.asicCount == 3)
        #expect(canaanSample.workmode == 2)
        #expect(canaanSample.pools.first?.pingMs == 33.0)
    }

    @Test("6. AxeForge /api/status is parsed and normalized into MinerInfo")
    func axeForgeStatusDriverAndFallback() async throws {
        let axeForgeJSON = Data(#"""
        {
          "status": "mining",
          "fault": "",
          "hashrate": 4950.5,
          "expected": 5000.0,
          "errorPct": 0.4,
          "chipTemp": 58.5,
          "vrTemp": 64.0,
          "vrSensor": true,
          "board": "AxeForge rev5.1/6 (TPS53647)",
          "asicModel": "BM1370",
          "asicCount": 4,
          "smallCores": 2040,
          "power": 74.5,
          "vin": 12.1,
          "vout": 1.18,
          "iout": 58.2,
          "freq": 600,
          "coreMv": 1180,
          "fanPct": 65,
          "fanRpm": 4100,
          "fan2Rpm": 3950,
          "fanCount": 2,
          "uptime": 14400,
          "rssi": -54,
          "hostname": "axeforge-nq",
          "worker": "bc1qaxeforge.nq1",
          "version": "v1.4.2",
          "dupResults": 3,
          "pool": {
            "connected": true,
            "host": "solo.ckpool.org:3333",
            "diff": 1024,
            "accepted": 256,
            "rejected": 2,
            "bestDiff": 850000000,
            "sessionBest": 120000000,
            "height": 885000,
            "networkDiff": 110000000000000,
            "blocks": 0,
            "mode": "failover"
          }
        }
        """#.utf8)

        let identity = await MinerFirmwareAdapter.identifyHost(
            "192.168.1.60",
            httpTransport: { req in
                if req.url?.path == "/api/status" {
                    return (axeForgeJSON, Self.httpResponse(url: req.url!))
                }
                return (Data(), Self.httpResponse(url: req.url!, status: 404))
            }
        )
        #expect(identity?.family == "axeForge")
        #expect(identity?.name == "axeforge-nq")
        #expect(identity?.model == "AxeForge rev5.1/6 (TPS53647)")
        let info = try #require(identity?.info)
        #expect(info.hashRate == 4950.5)
        #expect(info.expectedHashrate == 5000.0)
        #expect(info.power == 74.5)
        #expect(info.temp == 58.5)
        #expect(info.vrTemp == 64.0)
        #expect(info.fanSpeed == 65.0)
        #expect(info.fanRpm == 4100.0)
        #expect(info.fan2Rpm == 3950.0)
        #expect(info.frequency == 600.0)
        #expect(info.coreVoltage == 1180.0)
        #expect(info.voltage == 12100.0)
        #expect(info.sharesAccepted == 256)
        #expect(info.sharesRejected == 2)
        #expect(info.uptimeSeconds == 14400)
        #expect(info.poolURL == "solo.ckpool.org")
        #expect(info.blockHeight == 885000)
        #expect(!info.miningPaused)
        #expect(MinerShapeValidator.isValidInfoShape(.object(info.raw)))
    }

    @Test("Legacy cgminer pipe-delimited responses parse cleanly")
    func cgminerPipeDelimitedParsing() throws {
        let pipeText = "STATUS=S,When=1700000000,Code=11,Msg=Summary|SUMMARY,Elapsed=900,MHS av=6123456.0,Accepted=45,Rejected=1,Best Share=12345|"
        let parsed = try CgminerClient.parseResponse(pipeText)
        let summary = try #require(MinerDriverParse.sectionArray(parsed, key: "SUMMARY").first)
        #expect(MinerDriverParse.optInt(summary["Elapsed"]) == 900)
        #expect(MinerDriverParse.optFloat(summary["MHS av"]) == 6123456.0)
        #expect(MinerDriverParse.optInt(summary["Accepted"]) == 45)
    }

    private static func httpResponse(url: URL, status: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
    }
}
