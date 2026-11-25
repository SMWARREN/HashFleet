import Foundation
import Testing
@testable import HashFleetCore

/// Field names come from the ThorOS web console embedded in Hammer's published
/// `thorx1-1.0.6-20260916` and `thorp2-1.1.0-20261113` update images.
struct MinerThorOSDriverTests {
    private func object(_ json: String) throws -> [String: JSONValue] {
        try #require(try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)).objectValue)
    }

    private let minerStatus = """
    {"current_hashrate": 3200000000000, "power_consumption": 46.5, "power_efficiency": 14.5, \
    "temp_board": 55.5, "temp_vcore": 61, "input_voltage": 12.05, "core_voltage_actual": 0.42, \
    "frequency": 600, "fan_speed_rpm": 3100, "fan_target_speed": 70, "fan_mode": 0, \
    "shares_accepted": 120, "shares_rejected": 2, "bestDiff": "22M", "bestSessionDiff": "1.5M", \
    "pool_url": "solo.example.invalid", "pool_port": 3333, "pool_worker": "bc1qexample.x1", \
    "worker_password": "secret", "fallback_pool_url": "backup.example.invalid", \
    "fallback_pool_port": 4444, "isUsingFallbackStratum": false}
    """
    private let deviceInfo = """
    {"ok": true, "data": {"device_model": "THOR X1", "firmware_version": "1.0.6", \
    "hardware_version": "V00", "mac_address": "AA:BB:CC:DD:EE:FF", "chip_type": "BM1373", \
    "detected_chips_count": 1}}
    """

    @Test func recognizesInfoAndMinerStatusShapes() throws {
        #expect(MinerHTTPDrivers.isThorOSShape(try object(minerStatus)))
        #expect(MinerHTTPDrivers.isThorOSShape(try object(deviceInfo)))
        #expect(!MinerHTTPDrivers.isThorOSShape(try object(#"{"hashRate": 1000, "ASICModel": "BM1370"}"#)))
        #expect(!MinerHTTPDrivers.isThorOSShape(try object(#"{"device_model": "Other", "firmware_version": "1"}"#)))
    }

    @Test func parsesMergedPayloadIntoCanonicalUnits() throws {
        let sample = MinerHTTPDrivers.parseThorOS(
            info: try object(deviceInfo),
            deviceStatus: try object(#"{"uptime_seconds": 3600, "wifi_rssi": -55}"#),
            miner: try object(minerStatus),
            host: "192.0.2.10"
        )
        #expect(sample.family == "thorOS")
        #expect(sample.model == "THOR X1")
        #expect(sample.chipModel == "BM1373")
        #expect(sample.firmwareVersion == "1.0.6")
        #expect(sample.hashrateTHs == 3.2)
        #expect(sample.powerW == 46.5)
        #expect(sample.inputVoltageMV == 12_050)
        #expect(sample.voltageMV == 420)
        #expect(sample.frequencyMHz == 600)
        #expect(sample.tempChipC == 55.5)
        #expect(sample.uptimeS == 3600)
        #expect(sample.poolActive == "primary")
        #expect(sample.pools.count == 2)

        let info = sample.toMinerInfo(preservingFlatRaw: true)
        #expect(info.raw["firmwareFamily"]?.stringValue == "thorOS")
        #expect(info.raw["autofanspeed"]?.intValue == 1)
        #expect(info.raw["worker_password"] == nil)
        #expect(MinerFirmwareAdapter.detectedFamily(from: info) == "thorOS")
    }

    @Test func discoveryAcceptsThorInfoBody() {
        let found = FleetNetworkDiscovery.candidate(
            host: "192.0.2.10", statusCode: 200, contentType: "application/json", body: Data(deviceInfo.utf8)
        )
        #expect(found?.info.raw["firmwareFamily"]?.stringValue == "thorOS")
        #expect(found?.model == "BM1373")
    }

    @Test func htmlConsoleTriggersAlternativeProbe() {
        #expect(MinerHTTPDrivers.shouldProbeAlternativeDiscovery(statusCode: 200, contentType: "text/html"))
        #expect(MinerHTTPDrivers.shouldProbeAlternativeDiscovery(statusCode: 302, contentType: nil))
        #expect(MinerHTTPDrivers.shouldProbeAlternativeDiscovery(statusCode: 404, contentType: "text/plain"))
        #expect(!MinerHTTPDrivers.shouldProbeAlternativeDiscovery(statusCode: 200, contentType: "application/json"))
        #expect(MinerHTTPDrivers.alternativeDiscoveryPaths.contains("/v2/device/info"))
    }

    @Test func capabilitiesKeepVoltageReadOnly() {
        let caps = MinerDriverCapabilities.forFamily("thorOS")
        #expect(caps.family == "thorOS")
        #expect(caps.canSetFan && caps.canSetFrequency && caps.canRestart && caps.canSetPool)
        #expect(!caps.canSetVoltage)
    }
}
