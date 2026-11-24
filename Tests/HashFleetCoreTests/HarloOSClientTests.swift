import Foundation
import Testing
@testable import HashFleetCore

struct HarloOSClientTests {
    @Test func scheduleBodyMatchesFirmwareUI() throws {
        let b = try HarloOSClient.scheduleBody(enabled: true, days: [5, 1, 1], time: "7:05",
                                               action: .tuning(frequencyMHz: 525, coreMV: 1150))
        #expect(b["days"] == .array([.integer(1), .integer(5)]))
        #expect(b["time"] == .string("07:05"))
        #expect(b["method"] == .string("PUT") && b["path"] == .string("/api/tuning"))
        #expect(b["body"] == .object(["frequency_mhz": .integer(525), "core_mv": .integer(1150)]))
        let stop = try HarloOSClient.scheduleBody(enabled: false, days: [0], time: "23:59", action: .stop)
        #expect(stop["method"] == .string("POST") && stop["path"] == .string("/api/asic/stop"))
        let display = try HarloOSClient.scheduleBody(enabled: true, days: [2], time: "08:00", action: .display(on: false))
        #expect(display["path"] == .string("/api/display/mode") && display["body"] == .object(["mode": .string("off")]))
    }

    @Test func scheduleValidationRejectsBadInput() {
        #expect(throws: HarloOSError.self) { try HarloOSClient.scheduleBody(enabled: true, days: [], time: "10:00", action: .stop) }
        #expect(throws: HarloOSError.self) { try HarloOSClient.scheduleBody(enabled: true, days: [7], time: "10:00", action: .stop) }
        #expect(throws: HarloOSError.self) { try HarloOSClient.scheduleBody(enabled: true, days: [1], time: "24:00", action: .stop) }
        #expect(throws: HarloOSError.self) {
            try HarloOSClient.scheduleBody(enabled: true, days: [1], time: "10:00", action: .fanPercent(channel: 1, percent: 10))
        }
    }
}
