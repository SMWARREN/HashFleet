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
        for family in ["harloos", "nmaxe", "bitforge", "canaan", "canaannano3", "braiins", "luxos"] {
            #expect(MinerFirmwareExtras.controls(for: family).isEmpty, "\(family)")
        }
    }
}
