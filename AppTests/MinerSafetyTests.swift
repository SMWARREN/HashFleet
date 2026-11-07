import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

@Suite(.serialized) @MainActor
struct MinerSafetyTests {
    @Test func offlineGuardBlocksEveryMutationBeforeNetworking() async {
        let safetyEnv = fixture()
        let model = safetyEnv.model
        let session = safetyEnv.session
        let fixtureID = safetyEnv.fixtureID
        defer { session.invalidateAndCancel() }
        let device = MinerDevice(name: "Offline", address: "fixture.test")
        for endpoint in MinerEndpoint.catalog where MinerRequestSafety.isWrite(endpoint) {
            await model.execute(device: device, endpoint: endpoint, body: nil, query: [], isDemo: false)
            #expect(model.error?.contains("offline or stale") == true)
        }
        #expect(MinerSafetyProtocol.counter.value(fixtureID) == 0)
    }

    @Test func confirmedWriteStillRequiresAValidFreshInfoResponse() async {
        let device = MinerDevice(name: "Preflight", address: "fixture.test")
        for validInfo in [false, true] {
            let safetyEnv = fixture(validInfo: validInfo)
            let model = safetyEnv.model
            let session = safetyEnv.session
            let fixtureID = safetyEnv.fixtureID
            await model.execute(
                device: device,
                endpoint: .settings,
                body: Data("{\"hostname\":\"test\"}".utf8),
                query: [],
                isDemo: false,
                writeAuthorized: { true }
            )
            let methods = MinerSafetyProtocol.counter.methods(fixtureID)
            #expect(methods == (validInfo ? ["GET", "PATCH"] : ["GET"]))
            #expect((model.error == nil) == validInfo)
            session.invalidateAndCancel()
        }
    }

    @Test func writeAvailabilityRejectsOfflineMissingAndExpiredSnapshots() {
        let now = Date()
        let fresh = MinerSnapshot(info: MinerInfo(raw: ["hostname": .string("test")]), updatedAt: now)
        #expect(MinerWriteAvailability.allows(fresh, now: now))
        var reconnecting = fresh
        reconnecting.isReconnecting = true
        #expect(MinerWriteAvailability.allows(reconnecting, now: now) == false)
        #expect(!MinerWriteAvailability.allows(nil, now: now))
        var cached = fresh
        cached.error = "Cached · reconnect"
        #expect(!MinerWriteAvailability.allows(cached, now: now))
        cached.error = nil
        cached.updatedAt = now.addingTimeInterval(-301)
        #expect(!MinerWriteAvailability.allows(cached, now: now))
        cached.updatedAt = now.addingTimeInterval(61)
        #expect(!MinerWriteAvailability.allows(cached, now: now))
    }
    @Test func invalidAndEmptyJSONObjectsAreRejected() {
        for value in ["{}", "[]", "null", "42", "true", "{broken}"] {
            #expect(throws: (any Error).self) { try MinerRequestSafety.jsonData(value) }
        }
    }

    @Test func oversizedJSONIsRejected() {
        let oversized = "{\"custom\":\"" + String(repeating: "x", count: 256 * 1_024) + "\"}"
        #expect(throws: (any Error).self) { try MinerRequestSafety.jsonData(oversized) }
    }

    @Test func customPATCHFieldsAndFullNestedPoolObjectsArePreserved() throws {
        let original =
            #"{"customFirmwareField":true,"pools":[{"id":7,"stratumURL":"pool.test","stratumPort":3333,"# +
            #""stratumUser":"worker","stratumTLS":2,"stratumV2RequireAuth":true}]}"#
        let data = try MinerRequestSafety.jsonData(original)
        let object = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(object.objectValue?["customFirmwareField"]?.boolValue == true)
        let pool = try #require(object.objectValue?["pools"]?.arrayValue?.first?.objectValue)
        #expect(pool["id"]?.intValue == 7)
        #expect(pool["stratumTLS"]?.intValue == 2)
        #expect(pool["stratumV2RequireAuth"]?.boolValue == true)
    }

    @Test func reviewRedactsSecretsWithoutMutatingActualPayload() throws {
        let data = try MinerRequestSafety.jsonData(
            #"{"wifiPass":"wifi-secret","stratumPassword":"primary-secret","# +
            #""fallbackStratumPassword":"fallback-secret","pools":[{"id":7,"# +
            #""stratumPassword":"nested-secret","stratumUser":"visible-worker"}]}"#
        )
        let review = MinerRequestSafety.reviewedBody(data)
        for secret in ["wifi-secret", "primary-secret", "fallback-secret", "nested-secret"] {
            #expect(!review.contains(secret))
            #expect(String(bytes: data, encoding: .utf8)?.contains(secret) == true)
        }
        #expect(review.contains("visible-worker"))
        #expect(review.contains("will be sent"))
    }

    @Test func everyCatalogMutationRequiresReviewAndReadsRemainReads() {
        #expect(MinerEndpoint.catalog.count == 24)
        for endpoint in MinerEndpoint.catalog {
            let changesDevice = ["POST", "PATCH", "PUT", "DELETE"].contains(endpoint.method)
            #expect(MinerRequestSafety.isWrite(endpoint) == changesDevice)
        }
        for slot in 0...7 {
            #expect(MinerRequestSafety.isWrite(.updatePool(slot)))
            #expect(MinerRequestSafety.isWrite(.deletePool(slot)))
        }
    }

    @Test func highRiskChangesReceiveHardwareWarnings() {
        for field in [
            "coreVoltage", "frequency", "overheat_mode", "overclockEnabled", "autofanspeed", "manualFanSpeed",
            "minFanSpeed", "temptarget"
        ] {
            let data = Data("{\"\(field)\":1}".utf8)
            #expect(MinerRequestSafety.isHighRisk(.settings, data: data))
        }
        for endpoint in [MinerEndpoint.otaFirmware, .otaWWW, .boot] {
            #expect(MinerRequestSafety.isHighRisk(endpoint, data: nil))
        }
        #expect(!MinerRequestSafety.isHighRisk(.identify, data: nil))
        #expect(MinerRequestSafety.maximumUploadBytes == 16_777_216)
    }

    @Test func statisticsIntervalDoesNotImplyClockTuningButNestedHardwareStillWarns() {
        for json in [#"{"statsFrequency":30}"#, #"{"hostname":"frequency-miner"}"#] {
            #expect(!MinerRequestSafety.isHighRisk(.settings, data: Data(json.utf8)))
            #expect(MinerRequestSafety.isWrite(.settings))
        }
        #expect(MinerRequestSafety.isHighRisk(.settings, data: Data(#"{"custom":[{"minFanSpeed":25}]}"#.utf8)))
        #expect(MinerRequestSafety.isHighRisk(.settings, data: Data(#"{"statsFrequency":30,"frequency":500}"#.utf8)))
    }

    @Test func demoBlocksEveryHTTPRequestBeforeNetworking() async {
        let safetyEnv = fixture()
        let model = safetyEnv.model
        let session = safetyEnv.session
        let fixtureID = safetyEnv.fixtureID
        defer { session.invalidateAndCancel() }
        let device = MinerDevice(name: "Demo guard", address: "fixture.test")
        for endpoint in MinerEndpoint.catalog where !endpoint.isWebSocket {
            await model.execute(device: device, endpoint: endpoint, body: nil, query: [], isDemo: true)
            #expect(model.error?.contains("Demo mode") == true)
            #expect(!model.isRunning)
            #expect(model.exportedFile == nil)
        }
        #expect(MinerSafetyProtocol.counter.value(fixtureID) == 0)
    }

    @Test func demoWebSocketsNeverStart() {
        let model = MinerLiveModel()
        let device = MinerDevice(name: "Demo", address: "invalid address that cannot connect")
        for endpoint in [MinerEndpoint.liveWebSocket, .logWebSocket] {
            model.connect(device: device, endpoint: endpoint, isDemo: true)
            #expect(!model.isConnected)
            #expect(model.status.contains("Demo mode"))
            #expect(model.frames.isEmpty)
        }
    }

    @Test func successfulResponseStaysInMemoryUntilExplicitExport() async throws {
        let safetyEnv = fixture()
        let model = safetyEnv.model
        let session = safetyEnv.session
        let fixtureID = safetyEnv.fixtureID
        defer { session.invalidateAndCancel(); model.clearExport() }
        let device = MinerDevice(name: "Fixture", address: "fixture.test")
        await model.execute(device: device, endpoint: .info, body: nil, query: [], isDemo: false)
        #expect(model.error == nil)
        #expect(model.response.contains("fixture-response"))
        #expect(model.exportedFile == nil)
        #expect(MinerSafetyProtocol.counter.value(fixtureID) == 1)
        model.prepareExport(isLog: false)
        let file = try #require(model.exportedFile)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try Data(contentsOf: file) == MinerSafetyProtocol.payload)
        #expect(model.error == nil)
        model.clearExport()
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(model.exportedFile == nil)
        #expect(model.error == nil)
    }

    @Test func nextRequestRemovesPreviousExplicitExport() async throws {
        let safetyEnv = fixture()
        let model = safetyEnv.model
        let session = safetyEnv.session
        defer { session.invalidateAndCancel(); model.clearExport() }
        let device = MinerDevice(name: "Fixture", address: "fixture.test")
        await model.execute(device: device, endpoint: .logs, body: nil, query: [], isDemo: false)
        model.prepareExport(isLog: true)
        let file = try #require(model.exportedFile)
        await model.execute(device: device, endpoint: .info, body: nil, query: [], isDemo: false)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(model.exportedFile == nil)
        #expect(model.error == nil)
    }

    @Test func tuningPolicyIsIdentityBoundAndCannotBeRemovedByConflictingFirmwareMetadata() {
        let gamma = MinerDevice(name: "Renamed", address: "http://192.0.2.221:80")
        let conflict = MinerInfo(raw: ["boardVersion": .string("1201")])
        #expect(MinerTuningHardwarePolicy.maximumCoreVoltage(device: gamma, info: conflict) == 1150)
        let absoluteHost = MinerDevice(name: "Absolute host", address: "http://192.0.2.221.:80")
        #expect(MinerTuningHardwarePolicy.maximumCoreVoltage(device: absoluteHost, info: conflict) == 1150)
        #expect(MinerTuningHardwarePolicy.restriction(device: absoluteHost, voltage: 1151) != nil)
        #expect(MinerTuningHardwarePolicy.restriction(device: gamma, voltage: 1150) == nil)
        #expect(MinerTuningHardwarePolicy.restriction(device: gamma, voltage: 1151) != nil)
        let naja = MinerDevice(name: "Gamma 601a", address: "192.0.2.226")
        #expect(MinerTuningHardwarePolicy.maximumCoreVoltage(device: naja) == nil)
        let renamedHost = MinerDevice(name: "Other host", address: "miner.local")
        let reportedBoard = MinerInfo(raw: ["boardVersion": .string("601a")])
        #expect(MinerTuningHardwarePolicy.maximumCoreVoltage(device: renamedHost, info: reportedBoard) == 1150)
    }

    @Test func tuningVerificationMatchesEverySentFieldNotActualVoltageOrUntouchedFields() {
        let info = MinerInfo(raw: ["frequency": .number(535), "coreVoltage": .integer(1110),
                                   "coreVoltageActual": .integer(1105)])
        #expect(MinerTuningApplyService.matches(.object(["frequency": .number(535)]), info: info))
        #expect(MinerTuningApplyService.matches(.object(["coreVoltage": .integer(1110)]), info: info))
        #expect(!MinerTuningApplyService.matches(.object(["coreVoltage": .integer(1105)]), info: info))
        #expect(!MinerTuningApplyService.matches(.object(["frequency": .number(535),
                                                        "coreVoltage": .integer(1125)]), info: info))
        #expect(!MinerTuningApplyService.matches(.object([:]), info: info))
    }

    @Test func tunerApplyRequiresDedicatedPostWriteReadAndNeverLabelsMismatchVerified() async throws {
        for frequency in [500.0, 510.0] {
            let env = fixture(validInfo: true)
            defer { env.session.invalidateAndCancel() }
            let result = try await MinerTuningApplyService(session: env.session).apply(
                device: MinerDevice(name: "Fixture", address: "fixture.test"),
                payload: .object(["frequency": .number(frequency)]), isDemo: false, writeAuthorized: { true }
            )
            #expect(MinerSafetyProtocol.counter.methods(env.fixtureID) == ["GET", "PATCH", "GET"])
            switch result {
            case .verified(let info):
                #expect(frequency == 500)
                #expect(info.raw["frequency"]?.doubleValue == frequency)
            case .unverified(let message):
                #expect(frequency == 510)
                #expect(message.contains("draft is retained"))
            }
        }
    }

    @Test func tunerDemoOfflineAnd601aOvervoltageAreBlockedBeforeNetworking() async {
        for (demo, authorized, address, voltage) in [
            (true, true, "fixture.test", 1100.0), (false, false, "fixture.test", 1100.0),
            (false, true, "192.0.2.221", 1151.0)
        ] {
            let env = fixture(validInfo: true)
            defer { env.session.invalidateAndCancel() }
            do {
                _ = try await MinerTuningApplyService(session: env.session).apply(
                    device: MinerDevice(name: "Fixture", address: address),
                    payload: .object(["coreVoltage": .number(voltage)]), isDemo: demo,
                    writeAuthorized: { authorized }
                )
                Issue.record("Unsafe request should have been rejected")
            } catch {
                #expect(MinerSafetyProtocol.counter.value(env.fixtureID) == 0)
            }
        }
    }

    private struct SafetyFixture {
        let model: MinerOperationModel
        let session: URLSession
        let fixtureID: String
    }

    private func fixture(validInfo: Bool = false) -> SafetyFixture {
        let id = UUID().uuidString
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MinerSafetyProtocol.self]
        configuration.httpAdditionalHeaders = [
            "X-Miner-Safety-Fixture": id, "X-Miner-Safety-ValidInfo": validInfo ? "1" : "0"
        ]
        let session = URLSession(configuration: configuration)
        return SafetyFixture(model: MinerOperationModel(session: session), session: session, fixtureID: id)
    }
}

private final class MinerSafetyCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var journal: [String: [String]] = [:]
    func increment(_ id: String, method: String) {
        lock.withLock {
            counts[id, default: 0] += 1; journal[id, default: []].append(method)
        }
    }
    func value(_ id: String) -> Int { lock.withLock { counts[id, default: 0] } }
    func methods(_ id: String) -> [String] { lock.withLock { journal[id, default: []] } }
}

private class MinerSafetyProtocol: URLProtocol, @unchecked Sendable {
    static let counter = MinerSafetyCounter()
    static let payload = Data(#"{"message":"fixture-response"}"#.utf8)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.counter.increment(
            request.value(forHTTPHeaderField: "X-Miner-Safety-Fixture") ?? "unknown",
            method: request.httpMethod ?? "GET"
        )
        guard let url = request.url,
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let validInfo =
            request.url?.path == "/api/system/info"
            && request.value(forHTTPHeaderField: "X-Miner-Safety-ValidInfo") == "1"
        client?.urlProtocol(
            self,
            didLoad: validInfo ? Data(#"{"hostname":"fixture","hashRate":1000,"frequency":500,"coreVoltage":1150}"#.utf8) : Self.payload
        )
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
