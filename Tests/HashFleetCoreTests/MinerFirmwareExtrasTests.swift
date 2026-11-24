import Foundation
import Testing
@testable import HashFleetCore

/// Payloads must match each firmware's upstream handler exactly.
struct MinerFirmwareExtrasTests {
    private func control(_ family: String, _ key: String) throws -> MinerFirmwareExtra {
        try #require(MinerFirmwareExtras.controls(for: family).first { $0.key == key })
    }

    @Test func bitaxeTogglesSendIntegers() throws {
        // ESP-Miner TYPE_BOOL accepts numbers 0..1.
        let oc = try control("bitaxe", "overclockEnabled")
        #expect(oc.payload(1) == ["overclockEnabled": .integer(1)])
        #expect(oc.alwaysConfirm)
        #expect(oc.payload(2) == nil)
        #expect(oc.currentValue(in: ["overclockEnabled": .integer(1)]) == 1)
        #expect(try control("bitaxe", "useNTP").payload(0) == ["useNTP": .integer(0)])
    }

    @Test func nerdToggleSendsJSONBool() throws {
        // nq_handler_system.cpp checks doc["flipscreen"].is<bool>(): 0/1 would be ignored.
        #expect(try control("nerdqaxe", "flipscreen").payload(1) == ["flipscreen": .bool(true)])
        #expect(try control("bitfortun", "autoscreenoff").payload(0) == ["autoscreenoff": .bool(false)])
        let target = try control("nerdqaxe", "pidTargetTemp")
        #expect(target.payload(60) == ["pidTargetTemp": .integer(60)])
        #expect(target.payload(20) == nil)
        #expect(try control("nerdqaxe", "overheat_temp").alwaysConfirm)
    }

    @Test func axeForgeOverclockCarriesConfirmation() throws {
        let oc = try control("axeForge", "overclock")
        #expect(oc.payload(1) == ["overclock": .bool(true), "confirm": .string("OVERCLOCK")])
        #expect(oc.currentValue(in: ["overclock": .object(["unlocked": .bool(true)])]) == 1)
        #expect(try control("axeforge", "tgoal").payload(2) == ["tgoal": .integer(2)])
        #expect(try control("axeforge", "tgoal").payload(3) == nil)
        #expect(try control("axeforge", "pcap").payload(2001) == nil)
        #expect(MinerFirmwareExtras.supportsRetune("axeForge"))
    }

    @Test func axeForgeTranslationPassesExtrasThrough() throws {
        let body = try JSONEncoder().encode(JSONValue.object(["pcap": .integer(40), "atune": .bool(true)]))
        let out = try #require(MinerFirmwareAdapter.translateAxeForgeSettingsBody(body))
        guard case .object(let dict) = try JSONDecoder().decode(JSONValue.self, from: out) else {
            Issue.record("not object"); return
        }
        #expect(dict["pcap"] == .integer(40))
        #expect(dict["atune"] == .bool(true))
    }

    @Test func unverifiedFamiliesHaveNoExtras() {
        for family in ["nmaxe", "bitforge", "canaan", "canaannano3", "braiins", "luxos"] {
            #expect(MinerFirmwareExtras.controls(for: family).isEmpty, "\(family)")
        }
    }

    @Test func harloProtectionsSendAllFourThresholds() throws {
        let fan = try control("harloOS", "asic_fan_c")
        let doc: [String: JSONValue] = [
            "asic_fan_c": .integer(70), "asic_shutdown_c": .integer(85),
            "vr_fan_c": .integer(80), "vr_shutdown_c": .integer(95), "cooldown_seconds": .integer(60),
        ]
        #expect(fan.writePath == "/api/protections" && fan.writeMethod == "PUT" && fan.alwaysConfirm)
        #expect(fan.payload(72, document: doc) == [
            "asic_fan_c": .integer(72), "asic_shutdown_c": .integer(85),
            "vr_fan_c": .integer(80), "vr_shutdown_c": .integer(95),
        ])
        // Full-fan must stay below shutdown, and companions are required.
        #expect(fan.payload(85, document: doc) == nil)
        #expect(fan.payload(72) == nil)
        #expect(try control("harloos", "asic_shutdown_c").payload(70, document: doc) == nil)
    }

    @Test func harloDisplayUnitPowerAndCollection() throws {
        let display = try control("harloos", "mode")
        #expect(display.currentValue(in: ["mode": .string("clock"), "rotation": .integer(180)]) == 1)
        #expect(display.payload(2, document: ["rotation": .integer(180)])
                == ["mode": .string("off"), "rotation": .integer(180)])
        let unit = try control("harloos", "unit")
        #expect(unit.currentValue(in: ["temperature_unit": .string("F")]) == 1)
        #expect(unit.payload(0) == ["unit": .string("C")])
        let psu = try control("harloos", "rating_w")
        #expect(psu.currentValue(in: ["power_supply_rating_w": .integer(60)]) == 60)
        #expect(psu.payload(100) == ["rating_w": .integer(100)])
        #expect(psu.payload(0) == nil)
        #expect(try control("harloos", "enabled").payload(1) == ["enabled": .bool(true)])
    }

    @Test func harloActionsAndFaultNotice() throws {
        let actions = MinerFirmwareExtras.actions(for: "harloOS")
        let ack = try #require(actions.first { $0.id == "faultAck" })
        #expect(ack.path == "/api/alerts/acknowledge")
        #expect(!ack.isVisible(in: [:]))
        #expect(ack.isVisible(in: ["fault_notice_pending": .bool(true)]))
        #expect(actions.contains { $0.path == "/api/updates/check" })

        let sample = MinerHTTPDrivers.parseHarloOS(telemetry: [
            "hashrate_ghs": .number(0), "asic_temp_c": .number(91),
            "fault_notice_pending": .bool(true), "fault_notice_title": .string("OVERHEAT"),
            "fault_notice_reason": .string("ASIC reached 90 C"),
        ])
        #expect(sample.powerFault == "OVERHEAT: ASIC reached 90 C")
    }
}
