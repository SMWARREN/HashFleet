import Foundation
import Testing
@testable import HashFleetCore

/// Avalon cases from Canaan's A10 API manual and MinerWatch PR 17 (original Nano 3).
struct MinerCanaanEdgeCaseTests {
    private func version(_ json: String) throws -> [String: JSONValue] {
        try CgminerClient.parseResponse(json)
    }

    @Test func originalNano3IsFingerprintedFromVersion() throws {
        let v = try version(#"{"VERSION":[{"CGMiner":"4.11.1","API":"3.7","PROD":"Avalonnano","MODEL":"nano3","SWTYPE":"MM318_X2"}]}"#)
        #expect(MinerCgminerDrivers.fingerprint(versionResponse: v) == "canaannano3")
    }

    @Test func nano3sStaysOnGenericCanaan() throws {
        let v = try version(#"{"VERSION":[{"CGMiner":"4.11.1","API":"3.7","PROD":"Avalon Nano3s","MODEL":"Nano3s","SWTYPE":"MM319"}]}"#)
        #expect(MinerCgminerDrivers.fingerprint(versionResponse: v) == "canaan")
    }

    @Test func swtypeMM318AloneIdentifiesNano3() throws {
        let v = try version(#"{"VERSION":[{"CGMiner":"4.11.1","API":"3.7","SWTYPE":"MM318_X2"}]}"#)
        #expect(MinerCgminerDrivers.fingerprint(versionResponse: v) == "canaannano3")
    }

    @Test func estatsVerIdentifiesNano3AndNotNano3s() throws {
        let nano3 = try CgminerClient.parseResponse(#"{"STATS":[{"ID":"AVALON0","MM ID0":"Ver[nano3-24071801_abc] TMax[60]"}]}"#)
        let nano3s = try CgminerClient.parseResponse(#"{"STATS":[{"ID":"AVALON0","MM ID0":"Ver[Nano3s-25021401_56abae7] TMax[60]"}]}"#)
        #expect(MinerCgminerDrivers.estatsSaysNano3(nano3))
        #expect(!MinerCgminerDrivers.estatsSaysNano3(nano3s))
    }

    @Test func nano3PowerFallsBackToWallpowerThenPS6() throws {
        let v = try version(#"{"VERSION":[{"PROD":"Avalonnano","MODEL":"nano3"}]}"#)
        let wall = try CgminerClient.parseResponse(#"{"STATS":[{"MM ID0":"Ver[nano3-1] WALLPOWER[98] PS[0 0 27458 4 0 3990 130] WORKLEVEL[1]"}]}"#)
        let ps6 = try CgminerClient.parseResponse(#"{"STATS":[{"MM ID0":"Ver[nano3-1] PS[0 0 27458 4 0 3990 130] WORKLEVEL[2]"}]}"#)
        let a = MinerCgminerDrivers.parseCanaan(version: v, stats: wall, nano3: true)
        let b = MinerCgminerDrivers.parseCanaan(version: v, stats: ps6, nano3: true)
        #expect(a.powerW == 98)
        #expect(b.powerW == 130)
        #expect(a.workmode == 1)
        #expect(b.workmode == 2)
        #expect(a.model == "Avalon Nano 3")
        #expect(a.family == "canaannano3")
    }

    @Test func mpoWinsOverPS() throws {
        let v = try version(#"{"VERSION":[{"MODEL":"Nano3s"}]}"#)
        let s = try CgminerClient.parseResponse(#"{"STATS":[{"MM ID0":"Ver[Nano3s-1] MPO[133] PS[0 0 27458 4 0 3990 130] WORKMODE[2]"}]}"#)
        let sample = MinerCgminerDrivers.parseCanaan(version: v, stats: s)
        #expect(sample.powerW == 133)
        #expect(sample.workmode == 2)
        #expect(sample.powerFault == nil)
    }

    @Test func a10SixFieldPSUsesHashBoardWatts() throws {
        let v = try version(#"{"VERSION":[{"PROD":"AvalonMiner 1066"}]}"#)
        let s = try CgminerClient.parseResponse(#"{"STATS":[{"MM ID0":"Ver[1066-19101244] PS[0 1217 1279 221 2834 1280] WORKMODE[1]"}]}"#)
        #expect(MinerCgminerDrivers.parseCanaan(version: v, stats: s).powerW == 2834)
    }

    @Test func psErrorCodeBecomesPowerFault() throws {
        let v = try version(#"{"VERSION":[{"PROD":"AvalonMiner 1066"}]}"#)
        let s = try CgminerClient.parseResponse(#"{"STATS":[{"MM ID0":"Ver[1066-1] PS[2048 1217 1279 221 2834 1280]"}]}"#)
        let info = MinerCgminerDrivers.parseCanaan(version: v, stats: s).toMinerInfo()
        #expect(info.raw["power_fault"]?.stringValue == "Fan failed (PS error 2048)")
        #expect(MinerCgminerDrivers.powerSupplyFault(code: 34) == "PSU over temperature (OT1), Output voltage low (PS error 34)")
        #expect(MinerCgminerDrivers.powerSupplyFault(code: 0) == nil)
    }

    @Test func plainTextRepliesParse() throws {
        // A10 manual: text replies are `KEY=val,...|` sections.
        let text = "STATUS=S,When=6397,Code=70,Msg=CGMiner stats,Description=cgminer 4.11.1|STATS=0,ID=AVA100,MM ID0=Ver[1066-1] TMax[74] Fan1[3671] PS[0 1217 1279 221 2834 1280] WORKMODE[1],MM Count=1|"
        let stats = try CgminerClient.parseResponse(text)
        let v = try CgminerClient.parseResponse("STATUS=S,When=1,Code=22,Msg=CGMiner versions|VERSION,CGMiner=4.11.1,API=3.7,PROD=AvalonMiner 1066,MODEL=1066|")
        let sample = MinerCgminerDrivers.parseCanaan(version: v, stats: stats)
        #expect(sample.tempChipC == 74)
        #expect(sample.powerW == 2834)
        #expect(sample.workmode == 1)
        #expect(MinerFirmwareAdapter.isCgminerVersionResponse(v))
    }

    @Test func worklevelReplyParses() throws {
        #expect(MinerCgminerDrivers.parseWorklevelResponse(try CgminerClient.parseResponse(#"{"STATUS":[{"STATUS":"I","Msg":"worklevel 2"}]}"#)) == 2)
        #expect(MinerCgminerDrivers.parseWorklevelResponse(try CgminerClient.parseResponse("STATUS=I,When=1,Code=118,Msg=ASC 0 set info: WORKLEVEL[1],Description=cgminer 4.11.1|")) == 1)
    }

    @Test func nano3CapabilitiesHideFanFrequencyVoltage() {
        let caps = MinerDriverCapabilities.forFamily("canaannano3", info: nil)
        #expect(caps.canSetWorkmode && caps.canRestart)
        #expect(!caps.canSetFan && !caps.canSetFrequency && !caps.canSetVoltage)
    }

    @Test func nano3WritesUseNanoCliDialect() async throws {
        let sent = Sent()
        let transport: CgminerClient.Transport = { _, _, _, payload in
            let obj = try JSONDecoder().decode([String: String].self, from: payload)
            sent.add("\(obj["command"] ?? "")|\(obj["parameter"] ?? "")")
            return Data(#"{"STATUS":[{"STATUS":"I","Msg":"ok"}]}"#.utf8)
        }
        let device = MinerDevice(name: "n3", address: "192.0.2.9:4028", firmwareFamily: "canaannano3")
        let adapter = MinerFirmwareAdapter(device: device, cgminerTransport: transport)
        #expect(try await adapter.setWorkmode(1))
        #expect(try await adapter.restart())
        #expect(try await adapter.setFanSpeed(50) == false)
        #expect(try await adapter.setFrequency(500) == false)
        #expect(sent.all == ["ascset|0,worklevel,set,1", "ascset|0,reboot,all"])
    }

    @Test func webSocketsDoNotUseShortIdleTimeout() {
        #expect(MinerEndpoint.liveWebSocket.timeout >= 300)
        #expect(MinerEndpoint.info.timeout == 15)
    }

    private final class Sent: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
    }
}
