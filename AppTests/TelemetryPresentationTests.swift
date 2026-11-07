import Testing
import HashFleetCore
@testable import HashFleet

struct TelemetryPresentationTests {
    @Test func absentAndSentinelSensorsAreNotMeasuredZero() {
        let info = MinerInfo(raw: [
            "temp": .null, "vrTemp": .number(-1), "fanspeed": .number(0), "wifiRSSI": .number(-48)
        ])
        #expect(FleetFormat.sensor(info, keys: "temp") == nil)
        #expect(FleetFormat.sensor(info, keys: "vrTemp") == nil)
        #expect(FleetFormat.sensor(info, keys: "power") == nil)
        #expect(FleetFormat.sensor(info, keys: "fanspeed") == 0)
        #expect(FleetFormat.sensor(info, keys: "wifiRSSI", allowNegative: true) == -48)
        #expect(FleetFormat.measurement(nil, unit: "W") == "Not reported")
    }
}
