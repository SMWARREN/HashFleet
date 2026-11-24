import Foundation
import Testing
import HashFleetCore
@testable import HashFleetMac

/// Every family uses the shared Cooling and Frequency pages with its own reported keys.
struct CommonControlsRoutingTests {
    @Test func nerdPidTargetFeedsSharedCooling() throws {
        // nq_handler_system.cpp: autofanspeed 2 = PID, target in pidTargetTemp.
        let info = MinerInfo(raw: ["firmwareFamily": .string("nerdqaxe"), "autofanspeed": .integer(2),
                                   "pidTargetTemp": .integer(55), "manualFanSpeed": .integer(80)])
        var draft = MinerCoolingPreviewDraft(info: info)
        #expect(draft.automatic == true && draft[.target] == 55 && draft.hasControls)
        draft.adjust(.target, increasing: true)
        #expect(try draft.liveChanges(from: MinerCoolingPreviewDraft(info: info)) == ["temptarget": .integer(56)])
        draft.select(automatic: false)
        draft.select(automatic: true)
        let manualInfo = MinerInfo(raw: ["firmwareFamily": .string("bitfortun"), "autofanspeed": .integer(0),
                                         "pidTargetTemp": .integer(55), "manualFanSpeed": .integer(80)])
        var toAuto = MinerCoolingPreviewDraft(info: manualInfo)
        toAuto.select(automatic: true)
        #expect(try toAuto.liveChanges(from: MinerCoolingPreviewDraft(info: manualInfo))["autofanspeed"] == .integer(2))
    }

    @Test func avalonFanUsesSharedCoolingWithFirmwareMinimum() throws {
        let info = MinerInfo(raw: ["firmwareFamily": .string("canaan"), "fanspeed": .number(10),
                                   "deviceModel": .string("Avalon Nano3s")])
        var draft = MinerCoolingPreviewDraft(info: info)
        #expect(draft.hasControls && !draft.reportsMode && draft.automatic == nil)
        #expect(draft[.manual] == 15) // fan-spd accepts 15-100
        draft.select(automatic: false)
        #expect(draft.adjusted(.manual, increasing: false) == nil)
        draft.adjust(.manual, increasing: true)
        #expect(try draft.liveChanges(from: MinerCoolingPreviewDraft(info: info))
                == ["autofanspeed": .integer(0), "manualFanSpeed": .integer(16)])
        draft.select(automatic: true)
        #expect(try draft.liveChanges(from: MinerCoolingPreviewDraft(info: info)) == ["autofanspeed": .integer(1)])
    }

    @Test func avalonTuningIsFrequencyOnly() {
        let info = MinerInfo(raw: ["firmwareFamily": .string("canaan"), "frequency": .number(575),
                                   "coreVoltage": .number(3210)])
        #expect(MinerTuningPreviewDraft(info: info).fields == [.frequency])
        let bitaxe = MinerInfo(raw: ["frequency": .number(575), "coreVoltage": .number(1150)])
        #expect(MinerTuningPreviewDraft(info: bitaxe).fields == [.frequency, .coreVoltage])
    }
}
