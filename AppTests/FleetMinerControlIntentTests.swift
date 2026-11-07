import AppIntents
import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

struct FleetMinerControlIntentTests {
    @Test func systemAuthenticationIsRequiredForEveryHardwareIntent() {
        #expect(RestartFleetMinerIntent.authenticationPolicy == .requiresLocalDeviceAuthentication)
        #expect(SetFleetMinerFrequencyIntent.authenticationPolicy == .requiresLocalDeviceAuthentication)
        #expect(SetFleetMinerFanSpeedIntent.authenticationPolicy == .requiresLocalDeviceAuthentication)
    }

    @Test func invalidParametersFailBeforeReadOrConfirmation() async {
        for action in [
            FleetMinerControlAction.setFrequency(.nan), .setFrequency(.infinity),
            .setFrequency(0), .setFrequency(65536), .setFanSpeed(-1), .setFanSpeed(101)
        ] {
            let fixture = ControlFixture()
            await #expect(throws: FleetMinerControlError.self) {
                try await fixture.executor.run(deviceID: fixture.device.id.uuidString, action: action) { _ in
                    Issue.record("Invalid parameter reached confirmation")
                }
            }
            #expect(fixture.read { $0.reads } == 0)
            #expect(fixture.read { $0.writes.isEmpty })
        }
    }

    @Test func declinedConfirmationNeverPerformsSecondReadOrWrite() async {
        let fixture = ControlFixture()
        await #expect(throws: CancellationError.self) {
            try await fixture.executor.run(deviceID: fixture.device.id.uuidString, action: .restart) { prompt in
                #expect(prompt.contains(fixture.device.name))
                #expect(prompt.contains(fixture.device.address))
                #expect(fixture.read { $0.reads } == 1)
                #expect(fixture.read { $0.writes.isEmpty })
                throw CancellationError()
            }
        }
        #expect(fixture.read { $0.reads } == 1)
        #expect(fixture.read { $0.writes.isEmpty })
    }

    @Test func declinedParameterConfirmationBlocksEveryHardwareAction() async {
        for action in [
            FleetMinerControlAction.restart, .setFrequency(525), .setFanSpeed(70)
        ] {
            let fixture = ControlFixture()
            await #expect(throws: CancellationError.self) {
                try await fixture.executor.run(deviceID: fixture.device.id.uuidString, action: action) { prompt in
                    #expect(prompt.contains(fixture.device.name))
                    #expect(prompt.contains(fixture.device.address))
                    try FleetMinerControlConfirmation.requireApproval(false)
                }
            }
            #expect(fixture.read { $0.reads } == 1)
            #expect(fixture.read { $0.writes.isEmpty })
        }
    }

    @Test func approvedParameterConfirmationStillRequiresVerificationBeforeOneWrite() async throws {
        let fixture = ControlFixture()
        _ = try await fixture.executor.run(deviceID: fixture.device.id.uuidString, action: .restart) { _ in
            #expect(fixture.read { $0.reads } == 1)
            #expect(fixture.read { $0.writes.isEmpty })
            try FleetMinerControlConfirmation.requireApproval(true)
        }
        #expect(fixture.read { $0.reads } == 2)
        #expect(fixture.read { $0.writes.count } == 1)
    }

    @Test func exactFrequencyIsConfirmedAndOnlyFrequencyIsSent() async throws {
        let fixture = ControlFixture()
        let value = 525.123456789
        _ = try await fixture.executor.run(
            deviceID: fixture.device.id.uuidString, action: .setFrequency(value)
        ) { prompt in
            #expect(prompt.contains(String(value)))
            #expect(prompt.contains("not an established hardware-safe"))
            #expect(fixture.read { $0.writes.isEmpty })
        }
        let writes = fixture.read { $0.writes }
        #expect(writes.count == 1)
        #expect(fixture.read { $0.reads } == 2)
        #expect(writes.first?.endpoint == .settings)
        let body = try #require(writes.first?.body)
        let json = try JSONDecoder().decode(JSONValue.self, from: body)
        #expect(json.objectValue?.count == 1)
        #expect(json.objectValue?["frequency"]?.doubleValue == value)
    }

    @Test func fanConfirmationNamesAutoCoolingChangeAndExactPayload() async throws {
        let fixture = ControlFixture()
        _ = try await fixture.executor.run(
            deviceID: fixture.device.id.uuidString, action: .setFanSpeed(70)
        ) { prompt in
            #expect(prompt.contains("70%"))
            #expect(prompt.contains("disables automatic cooling"))
        }
        let body = try #require(fixture.read { $0.writes.first?.body })
        let json = try JSONDecoder().decode(JSONValue.self, from: body)
        #expect(json.objectValue?.count == 2)
        #expect(json.objectValue?["autofanspeed"]?.doubleValue == 0)
        #expect(json.objectValue?["manualFanSpeed"]?.doubleValue == 70)
    }

    @Test func restartSendsExactlyOneBodylessPost() async throws {
        let fixture = ControlFixture()
        _ = try await fixture.executor.run(deviceID: fixture.device.id.uuidString, action: .restart) { _ in }
        let writes = fixture.read { $0.writes }
        #expect(writes.count == 1)
        #expect(writes.first?.endpoint == .restart)
        #expect(writes.first?.endpoint.method == "POST")
        #expect(writes.first?.body == nil)
    }

    @Test func demoMissingAndInvalidTargetsFailBeforeNetwork() async {
        for mode in 0..<3 {
            let fixture = ControlFixture()
            fixture.mutate {
                if mode == 0 { $0.demo = true }
                if mode == 1 { $0.devices = [] }
                if mode == 2 { $0.devices[0].address = "http://name:password@miner.local" }
            }
            await #expect(throws: FleetMinerControlError.self) {
                try await fixture.executor.run(deviceID: fixture.device.id.uuidString, action: .restart) { _ in
                    Issue.record("Invalid target reached confirmation")
                }
            }
            #expect(fixture.read { $0.reads } == 0)
            #expect(fixture.read { $0.writes.isEmpty })
        }
    }

    @Test func staleConfirmationIsRejectedWithoutWrite() async {
        let fixture = ControlFixture()
        await #expect(throws: FleetMinerControlError.self) {
            try await fixture.executor.run(deviceID: fixture.device.id.uuidString, action: .restart) { _ in
                fixture.mutate { $0.now = $0.now.addingTimeInterval(FleetGlance.freshnessInterval * 3 + 1) }
            }
        }
        #expect(fixture.read { $0.writes.isEmpty })
    }

    @Test func failuresAndMalformedInfoBlockMutationAtEitherRead() async {
        for index in [1, 2] {
            for invalidShape in [false, true] {
                let fixture = ControlFixture()
                fixture.mutate {
                    if invalidShape { $0.invalidInfoAtRead = index } else { $0.failAtRead = index }
                }
                await #expect(throws: FleetMinerControlError.self) {
                    try await fixture.executor.run(deviceID: fixture.device.id.uuidString, action: .restart) { _ in }
                }
                #expect(fixture.read { $0.writes.isEmpty })
            }
        }
    }

    @Test func savedTargetAndDemoAreRecheckedAfterAwaitedRead() async {
        for mutation in ControlFixture.ReadMutation.allCases {
            let fixture = ControlFixture()
            fixture.mutate { $0.secondReadMutation = mutation }
            await #expect(throws: FleetMinerControlError.self) {
                try await fixture.executor.run(deviceID: fixture.device.id.uuidString, action: .restart) { _ in }
            }
            #expect(fixture.read { $0.writes.isEmpty })
        }
    }

    @Test func cancelledTaskCannotWriteAfterConfirmation() async {
        let fixture = ControlFixture()
        let task = Task {
            try await fixture.executor.run(deviceID: fixture.device.id.uuidString, action: .restart) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(fixture.read { $0.writes.isEmpty })
    }

    @Test func failedMutationIsNeverRetried() async {
        let fixture = ControlFixture()
        fixture.mutate { $0.failWrite = true }
        await #expect(throws: FleetMinerControlError.self) {
            try await fixture.executor.run(deviceID: fixture.device.id.uuidString, action: .restart) { _ in }
        }
        #expect(fixture.read { $0.writes.count } == 1)
    }

    @Test func entityQueryMatchesSavedIdentityAndFiltersInvalidAddresses() async throws {
        let fixture = ControlFixture()
        let invalid = MinerDevice(name: "Invalid", address: "https://user:pass@miner.local")
        let query = FleetMinerEntityQuery(loader: { [fixture.device, invalid] })
        #expect(try await query.suggestedEntities().count == 1)
        #expect(
            try await query.entities(for: [fixture.device.id.uuidString]).first?.id == fixture.device.id.uuidString
        )
        #expect(try await query.entities(matching: "workshop").count == 1)
        #expect(try await query.entities(for: [UUID().uuidString]).isEmpty)
    }
}

/// All mutable fixture state is locked. No live network or real saved-device storage.
private final class ControlFixture: @unchecked Sendable {
    enum ReadMutation: CaseIterable { case remove, changeAddress, demo }
    struct Write { let endpoint: MinerEndpoint; let body: Data? }
    struct State {
        var devices: [MinerDevice]
        var demo = false
        var reads = 0
        var writes: [Write] = []
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        var failAtRead: Int?
        var invalidInfoAtRead: Int?
        var secondReadMutation: ReadMutation?
        var failWrite = false
    }
    let device = MinerDevice(name: "Workshop Gamma", address: "fixture.invalid")
    private let lock = NSLock()
    private var state: State
    init() { state = State(devices: [device]) }
    func read<T>(_ body: (State) -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body(state)
    }
    func mutate<T>(_ body: (inout State) throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body(&state)
    }
    var executor: FleetMinerControlExecutor {
        FleetMinerControlExecutor(
            savedDevicesLoader: { self.read { $0.devices } },
            demoChecker: { self.read { $0.demo } },
            infoFetcher: { _ in
                try self.mutate { state in
                    state.reads += 1
                    if state.reads == state.failAtRead { throw URLError(.timedOut) }
                    if state.reads == 2 {
                        switch state.secondReadMutation {
                        case .remove: state.devices = []
                        case .changeAddress: state.devices[0].address = "different.invalid"
                        case .demo: state.demo = true
                        case nil: break
                        }
                    }
                    if state.reads == state.invalidInfoAtRead { return MinerInfo(raw: [:]) }
                    return MinerInfo(raw: [
                        "hostname": .string("workshop-gamma"), "version": .string("2.13.1"),
                        "hashRate": .number(1200), "frequency": .number(500), "temp": .number(58)
                    ])
                }
            },
            writeExecutor: { _, endpoint, body in
                try self.mutate {
                    $0.writes.append(Write(endpoint: endpoint, body: body))
                    if $0.failWrite { throw URLError(.networkConnectionLost) }
                }
                return Data()
            },
            dateProvider: { self.read { $0.now } }
        )
    }
}
