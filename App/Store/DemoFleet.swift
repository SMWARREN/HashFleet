import Foundation
import HashFleetCore

enum DemoFleet {
    enum HistoryMode {
        case populated
        case empty
        case staleDaily
    }

    static var devices: [MinerDevice] {
        [
            MinerDevice(name: "Workshop Gamma", address: "gamma-demo.invalid"),
            MinerDevice(name: "Office Gamma", address: "office-demo.invalid"),
            MinerDevice(name: "Little Supra", address: "supra-demo.invalid")
        ]
    }

    /// Additional deterministic CPU host for native mixed-algorithm acceptance, not live telemetry.
    static var mixedDevices: [MinerDevice] {
        devices + [MinerDevice(name: "Sample CPU", address: "cpu-demo.invalid", kind: .xmrig)]
    }

    /// One synthetic miner per supported pool preset. Never copied from the user's real fleet.
    static var poolIconDevices: [MinerDevice] {
        SoloPoolPreset.allCases.indices.map { index in
            MinerDevice(
                name: "Demo \(index.isMultiple(of: 2) ? "Gamma" : "Supra") \(index + 1)",
                address: "pool-icon-\(index).invalid"
            )
        }
    }

    static func poolIconSnapshots(for devices: [MinerDevice]) -> [UUID: MinerSnapshot] {
        var result = snapshots(for: devices)
        let pools: JSONValue = .array(
            SoloPoolPreset.allCases.enumerated().map { slot, preset in
                .object([
                    "id": .integer(Int64(slot)), "stratumURL": .string(preset.server),
                    "stratumPort": .integer(Int64(preset.port))
                ])
            }
        )
        for (index, device) in devices.enumerated() {
            guard var snapshot = result[device.id], var raw = snapshot.info?.raw else { continue }
            raw["pools"] = pools
            raw["activePoolIndex"] = .integer(Int64(index % SoloPoolPreset.allCases.count))
            raw["isUsingFallbackStratum"] = .integer(0)
            raw["ASICModel"] = .string(index.isMultiple(of: 2) ? "BM1370" : "BM1368")
            raw["version"] = .string("Mock pool icon preview")
            snapshot.info = MinerInfo(raw: raw)
            result[device.id] = snapshot
        }
        return result
    }

    static func snapshots(for devices: [MinerDevice], historyMode: HistoryMode = .populated) -> [UUID: MinerSnapshot] {
        var result: [UUID: MinerSnapshot] = [:]
        let rates = [1218.0, 1164.0, 638.0]
        let now = Date()
        for (index, device) in devices.enumerated() {
            let rate = device.kind == .xmrig ? 2_100.0 / 1_000_000_000 : rates[index % rates.count]
            let raw = sampleRawInfo(for: device, index: index, rate: rate)
            let history = sampleHistory(rate: rate, index: index, now: now, mode: historyMode)
            result[device.id] = MinerSnapshot(info: MinerInfo(raw: raw), error: nil, updatedAt: now, history: history)
        }
        return result
    }

    private static func sampleRawInfo(for device: MinerDevice, index: Int, rate: Double) -> [String: JSONValue] {
        if device.kind == .xmrig {
            return [
                "hostname": .string(device.name), "hashRate": .number(rate),
                "version": .string("XMRig demo fixture"), "algorithm": .string("rx/0"),
                "sharesAccepted": .integer(64), "sharesRejected": .integer(0),
                "uptimeSeconds": .integer(3_600), "miningPaused": .bool(false)
            ]
        }
        let uiTestFallbackNotice = ProcessInfo.processInfo.arguments.contains("--ui-test-fallback-notice")
        var raw: [String: JSONValue] = [
            "hostname": .string(device.name), "hashRate": .number(rate),
            "power": .number(index == 2 ? 12.4 : 19.2), "temp": .number(53 + Double(index) * 3),
            "vrTemp": .number(61 + Double(index)), "fanspeed": .number(65),
            "fanrpm": .number(4200 + Double(index) * 200), "voltage": .number(5200),
            "frequency": .number(index == 2 ? 525 : 575), "coreVoltage": .number(1150),
            "sharesAccepted": .number(12486 + Double(index) * 720), "sharesRejected": .number(3),
            "uptimeSeconds": .number(245820), "version": .string("Demo fixture"),
            "ASICModel": .string(index == 2 ? "BM1368" : "BM1370"),
            "asicCount": .integer(2),
            "statsFrequency": .integer(30), "autofanspeed": .integer(1), "temptarget": .integer(55),
            "bestDiff": .string("18.4G"), "bestSessionDiff": .string("9.2M"),
            "stratumURL": .string("solo.ckpool.org"),
            "primaryPoolIndex": .integer(0), "secondaryPoolIndex": .integer(1),
            "isUsingFallbackStratum": .integer(uiTestFallbackNotice && index == 0 ? 1 : 0),
            "fallbackStratumURL": .string("bch.solofury.com"),
            "pools": .array([
                .object([
                    "id": .integer(0), "stratumURL": .string("stratum.ckpool.org"),
                    "stratumUser": .string("1BoatSLRHtKNngkdXEeobR76b53LETtpyT.demo")
                ]),
                .object([
                    "id": .integer(1), "stratumURL": .string("bch.solofury.com"),
                    "stratumUser": .string("bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a.demo")
                ])
            ]),
            "wifiRSSI": .number(-48)
        ]
        if ProcessInfo.processInfo.arguments.contains("--ui-test-pool-rotation") {
            raw["activePoolIndex"] = .integer(1)
            raw["poolRotationEnabled"] = .bool(true)
        }
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing"), arguments.contains("--ui-test-asic-telemetry") {
            // Explicitly synthetic, opt-in UI evidence. The ordinary demo and every real
            // snapshot retain their original data. This never reads a miner endpoint.
            let domainRates = (0..<8).map { domain in
                JSONValue.number(rate / 16 + (Double(domain) - 3.5) * 0.25)
            }
            raw["hashrateMonitor"] = .object(["asics": .array([
                .object(["domains": .array(domainRates)]),
                .object(["domains": .array(domainRates)])
            ])])
            raw["expectedHashrate"] = .number(rate)
            raw["version"] = .string("Demo ASIC register fixture")
        }
        return raw
    }

    private static func sampleHistory(rate: Double, index: Int, now: Date, mode: HistoryMode) -> [HashratePoint] {
        switch mode {
        case .populated:
            return (0..<60).map { point in
                HashratePoint(
                    date: now.addingTimeInterval(Double(point - 59) * 10),
                    value: rate + sin(Double(point) * 0.65 + Double(index)) * (rate < 1 ? rate * 0.04 : 42)
                )
            }
        case .empty:
            return []
        case .staleDaily:
            return [HashratePoint(date: now.addingTimeInterval(-2 * 24 * 60 * 60), value: rate)]
        }
    }
}
