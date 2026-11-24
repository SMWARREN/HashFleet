import Foundation
import Testing
@testable import HashFleetCore

/// Bodies captured from the virtual-miner-lab LAN mocks (.205 AxeForge, .206 Harlo-OS).
struct MinerLabShapeDiscoveryTests {
    @Test func axeForgeStatusBodyIsDiscovered() throws {
        let json = """
        {"version": "1.5.0", "board": "Bitaxe Gamma Hex", "asicModel": "BM1370", \
        "status": "mining", "freq": 525, "fanPct": 60, "fanRpm": 2200, "chipTemp": 52.0, \
        "power": 37.64, "hashrate": 1.79, "coreMv": 1150, "atune": true, "fmode0": 0, "fman0": 60}
        """
        let body = Data(json.utf8)
        let found = FleetNetworkDiscovery.candidate(
            host: "192.168.86.205", statusCode: 200, contentType: "application/json", body: body
        )
        #expect(found != nil)
        #expect(found?.info.raw["firmwareFamily"]?.stringValue == "axeForge")
    }

    @Test func harloTelemetryBodyIsDiscovered() throws {
        let json = """
        {"hashrate_ghs": 1.06, "device_power_w": 18.59, "asic_temp_c": 53.5, \
        "powered": true, "frequency_mhz": 525, "fan_duty_pct": 100, "fans": [{"channel": 1, "percent": 100}]}
        """
        let body = Data(json.utf8)
        let found = FleetNetworkDiscovery.candidate(
            host: "192.168.86.206", statusCode: 200, contentType: "application/json", body: body
        )
        #expect(found != nil)
        #expect(found?.info.raw["firmwareFamily"]?.stringValue == "harloOS")
    }
}
