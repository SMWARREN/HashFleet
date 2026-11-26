import Foundation
import HashFleetCore
@testable import HashFleetMac

/// Shared in-memory miner fixtures for offline evaluation tests. These are plain values:
/// no network, no sockets, and no real device. Each builder sets the state one branch reads.
enum MinerFixtures {
    /// A healthy ESP-Miner reading with every field the tuning and cooling views consume.
    static func healthyFields(family: String = "bitaxe") -> [String: JSONValue] {
        [
            "hostname": .string("Rig"), "firmwareFamily": .string(family),
            "ASICModel": .string("BM1370"), "deviceModel": .string("Gamma"),
            "version": .string("2.12.0"), "macAddr": .string("aa:bb:cc:dd:ee:ff"),
            "frequency": .number(525), "coreVoltage": .number(1060),
            "temp": .number(62), "vrTemp": .number(55), "power": .number(14),
            "fanspeed": .number(60), "manualFanSpeed": .number(60), "minFanSpeed": .number(20),
            "autofanspeed": .bool(false), "temptarget": .number(65),
            "hashRate": .number(900), "expectedHashrate": .number(950),
            "sharesAccepted": .integer(120), "sharesRejected": .integer(2),
            "uptimeSeconds": .integer(3600), "wifiRSSI": .integer(-55)
        ]
    }

    /// A reading in a hot or faulted state, so warning and error branches render.
    static func faultedFields() -> [String: JSONValue] {
        var fields = healthyFields()
        fields["temp"] = .number(88)
        fields["vrTemp"] = .number(94)
        fields["power_fault"] = .string("sag")
        fields["overheat_mode"] = .bool(true)
        fields["miningPaused"] = .bool(true)
        fields["hashRate"] = .number(120)
        fields["sharesRejected"] = .integer(48)
        return fields
    }

    /// A reading with no optional telemetry, so "Not reported" fallbacks run.
    static func sparseFields() -> [String: JSONValue] {
        ["hostname": .string("Sparse"), "firmwareFamily": .string("bitaxe")]
    }

    static func snapshot(_ raw: [String: JSONValue], error: String? = nil, isCached: Bool = false) -> MinerSnapshot {
        MinerSnapshot(
            info: MinerInfo(raw: raw), previousInfo: nil, error: error, updatedAt: Date(),
            completeSnapshotAt: Date(), powerObservedAt: Date(),
            history: [], isCached: isCached, isReconnecting: false
        )
    }

    /// A miner device with an unreachable placeholder address. Nothing connects to it in tests.
    static func device(
        name: String = "Rig", kind: MinerDevice.Kind = .espMiner, family: String = "bitaxe"
    ) -> MinerDevice {
        MinerDevice(name: name, address: "192.168.1.40", kind: kind, firmwareFamily: family)
    }
}
