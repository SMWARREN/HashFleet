import Foundation
import Testing
@testable import HashFleetCore

private final class WriteTestRecorder: @unchecked Sendable {
    let lock = NSLock()
    var requests: [String: [URLRequest]] = [:]
    var responses: [String: (URLRequest) -> (Int, Data)] = [:]

    func register(id: String, handler: @escaping (URLRequest) -> (Int, Data)) {
        lock.withLock {
            requests[id] = []
            responses[id] = handler
        }
    }

    func record(id: String, request: URLRequest) -> (Int, Data) {
        lock.withLock {
            requests[id, default: []].append(request)
            let handler = responses[id]
            return handler?(request) ?? (200, Data(#"{"ok":true}"#.utf8))
        }
    }

    func history(id: String) -> [URLRequest] {
        lock.withLock { requests[id] ?? [] }
    }
}

private let sharedWriteRecorder = WriteTestRecorder()

private final class WriteTestURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private func capturedRequest() -> URLRequest {
        var copy = request
        if copy.httpBody == nil, let stream = copy.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buf = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = stream.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                data.append(contentsOf: buf.prefix(n))
            }
            copy.httpBody = data
        }
        return copy
    }

    override func startLoading() {
        let captured = capturedRequest()
        let id = captured.value(forHTTPHeaderField: "X-Write-Test-ID") ?? "default"
        let (status, body) = sharedWriteRecorder.record(id: id, request: captured)
        let response = HTTPURLResponse(
            url: captured.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Per-firmware write drivers & endpoint translation")
struct MinerWriteDriversTests {
    private func makeSession(
        id: String,
        handler: @escaping (URLRequest) -> (Int, Data) = { _ in (200, Data(#"{"ok":true}"#.utf8)) }
    ) -> URLSession {
        sharedWriteRecorder.register(id: id, handler: handler)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WriteTestURLProtocol.self]
        config.httpAdditionalHeaders = ["X-Write-Test-ID": id]
        return URLSession(configuration: config)
    }

    @Test("Driver capabilities match MinerWatch + AxeForge matrix")
    func driverCapabilitiesMatrix() {
        let bitaxe = MinerDriverCapabilities.forFamily("bitaxe")
        #expect(bitaxe.canSetFan && bitaxe.canSetFrequency && bitaxe.canSetVoltage)
        #expect(bitaxe.canRestart && bitaxe.canPause && !bitaxe.canShutdown && bitaxe.canSetPool)

        let nerd = MinerDriverCapabilities.forFamily("nerdqaxe")
        #expect(nerd.canSetFan && nerd.canSetFrequency && nerd.canSetVoltage)
        #expect(nerd.canRestart && !nerd.canPause && nerd.canShutdown && nerd.canSetPool)

        let forgeWithPause = MinerDriverCapabilities.forFamily(
            "bitforge", info: MinerInfo(raw: ["miningPaused": .bool(false)])
        )
        #expect(forgeWithPause.canPause)
        let forgeNoPause = MinerDriverCapabilities.forFamily(
            "bitforge", info: MinerInfo(raw: ["hashRate": .number(2200)])
        )
        #expect(!forgeNoPause.canPause)

        let nmaxe = MinerDriverCapabilities.forFamily("nmaxe")
        #expect(nmaxe.canSetFan && nmaxe.canRestart)
        #expect(!nmaxe.canSetFrequency && !nmaxe.canSetVoltage && !nmaxe.canSetPool)

        let axeForge = MinerDriverCapabilities.forFamily("axeForge")
        #expect(axeForge.canSetFan && axeForge.canSetFrequency && axeForge.canSetVoltage)
        #expect(axeForge.canRestart && axeForge.canIdentify && axeForge.canSetPool && axeForge.fanMinPct == 20)

        let harloOS = MinerDriverCapabilities.forFamily("harloOS")
        #expect(harloOS.canSetFan && harloOS.canSetFrequency && harloOS.canSetVoltage)
        #expect(harloOS.canRestart && harloOS.canPause && harloOS.canShutdown && harloOS.canSetPool && harloOS.fanMinPct == 20)

        let canaan = MinerDriverCapabilities.forFamily("canaan")
        #expect(canaan.canSetFan && canaan.canSetFrequency && canaan.canSetVoltage)
        #expect(canaan.canSetWorkmode && canaan.canRestart && canaan.fanMinPct == 15)

        #expect(MinerDriverCapabilities.forFamily("braiins").isReadOnly)
        #expect(MinerDriverCapabilities.forFamily("luxos").isReadOnly)
    }

    @Test("BitForge fan write sends all three fan key spellings (fanspeed, fanSpeed, manualFanSpeed)")
    func bitForgeFanWriteSpellings() async throws {
        let id = UUID().uuidString
        let session = makeSession(id: id)
        defer { session.invalidateAndCancel() }

        let device = MinerDevice(name: "BitForge Nano", address: "192.168.1.51", firmwareFamily: "bitforge")
        let adapter = MinerFirmwareAdapter(device: device, session: session)

        #expect(try await adapter.setFanSpeed(75))
        let history = sharedWriteRecorder.history(id: id)
        #expect(history.count == 1)
        #expect(history[0].httpMethod == "PATCH")
        #expect(history[0].url?.path == "/api/system")
        let body = try JSONDecoder().decode(JSONValue.self, from: try #require(history[0].httpBody))
        #expect(body["autofanspeed"]?.intValue == 0)
        #expect(body["fanspeed"]?.intValue == 75)
        #expect(body["fanSpeed"]?.intValue == 75)
        #expect(body["manualFanSpeed"]?.intValue == 75)

        // Also verify execute(.settings) translates a standard HashFleet fan payload for BitForge
        let stdBody = try JSONEncoder().encode(
            JSONValue.object(["autofanspeed": .integer(0), "manualFanSpeed": .integer(65)])
        )
        _ = try await adapter.execute(.settings, body: stdBody)
        let second = try JSONDecoder().decode(
            JSONValue.self, from: try #require(sharedWriteRecorder.history(id: id).last?.httpBody)
        )
        #expect(second["fanspeed"]?.intValue == 65)
        #expect(second["fanSpeed"]?.intValue == 65)
        #expect(second["manualFanSpeed"]?.intValue == 65)
    }

    @Test("NerdQAxe maps pause to /api/system/shutdown and resume to /api/system/restart")
    func nerdQAxeShutdownAndResumeMapping() async throws {
        let id = UUID().uuidString
        let session = makeSession(id: id)
        defer { session.invalidateAndCancel() }

        let device = MinerDevice(name: "NerdOCTAXE", address: "192.168.1.53", firmwareFamily: "nerdqaxe")
        let adapter = MinerFirmwareAdapter(device: device, session: session)

        _ = try await adapter.execute(.pause)
        _ = try await adapter.execute(.resume)

        let history = sharedWriteRecorder.history(id: id)
        #expect(history.count == 2)
        #expect(history[0].httpMethod == "POST")
        #expect(history[0].url?.path == "/api/system/shutdown")
        #expect(history[1].httpMethod == "POST")
        #expect(history[1].url?.path == "/api/system/restart")
    }

    @Test("NMAxe fan writes route to PATCH /api/setting/preference")
    func nmaxeFanPreferenceWrites() async throws {
        let id = UUID().uuidString
        let session = makeSession(id: id)
        defer { session.invalidateAndCancel() }

        let device = MinerDevice(name: "NMQAxe++", address: "192.168.1.50", firmwareFamily: "nmaxe")
        let adapter = MinerFirmwareAdapter(device: device, session: session)

        #expect(try await adapter.setFanSpeed(80))
        #expect(try await adapter.setAutoFan(true))

        // Standard HashFleet .settings payload with manualFanSpeed is also translated to /api/setting/preference
        let stdFan = try JSONEncoder().encode(
            JSONValue.object(["autofanspeed": .integer(0), "manualFanSpeed": .integer(60)])
        )
        _ = try await adapter.execute(.settings, body: stdFan)

        let history = sharedWriteRecorder.history(id: id)
        #expect(history.count == 3)
        for req in history {
            #expect(req.httpMethod == "PATCH")
            #expect(req.url?.path == "/api/setting/preference")
        }
        let firstJSON = try JSONDecoder().decode(JSONValue.self, from: try #require(history[0].httpBody))
        let firstFan = try #require(firstJSON["fans"]?.arrayValue?.first?.objectValue)
        #expect(firstFan["id"]?.intValue == 0)
        #expect(firstFan["auto"]?.boolValue == false)
        #expect(firstFan["speed"]?.intValue == 80)

        let secondJSON = try JSONDecoder().decode(JSONValue.self, from: try #require(history[1].httpBody))
        let secondFan = try #require(secondJSON["fans"]?.arrayValue?.first?.objectValue)
        #expect(secondFan["auto"]?.boolValue == true)
    }

    @Test("AxeForge write operations send X-AxeForge: 1 header and translate settings & endpoints")
    func axeForgeWritesAndHeaderGuard() async throws {
        let id = UUID().uuidString
        let session = makeSession(id: id) { req in
            if req.url?.path == "/api/pools" && req.httpMethod == "GET" {
                let poolsData = Data(#"""
                {"pools":[{"enabled":true,"url":"solo.ckpool.org","port":3333,"user":"bc1q1","pass":"x"}],"mode":"failover"}
                """#.utf8)
                return (200, poolsData)
            }
            return (200, Data(#"{"ok":true}"#.utf8))
        }
        defer { session.invalidateAndCancel() }

        let device = MinerDevice(name: "AxeForge NQ", address: "192.168.1.60", firmwareFamily: "axeForge")
        let adapter = MinerFirmwareAdapter(device: device, session: session)

        // 1. Direct write methods
        #expect(try await adapter.setFrequency(625))
        #expect(try await adapter.setVoltage(1180))
        #expect(try await adapter.setFanSpeed(70))
        #expect(try await adapter.restart())
        #expect(try await adapter.identify())

        // 2. Pool read & write
        let poolCfg = try await adapter.readPoolConfig()
        #expect(poolCfg.url == "solo.ckpool.org")
        #expect(poolCfg.port == 3333)
        #expect(poolCfg.user == "bc1q1")
        #expect(try await adapter.setPool(MinerPoolConfig(url: "pool.braiins.com", port: 3333, user: "w1")))

        // 3. Unified execute(.settings) translation from HashFleet tuning payload
        let tuningBody = try JSONEncoder().encode(
            JSONValue.object(["frequency": .number(650), "coreVoltage": .integer(1200)])
        )
        _ = try await adapter.execute(.settings, body: tuningBody)

        let history = sharedWriteRecorder.history(id: id)
        // Every POST request to AxeForge must carry X-AxeForge: 1
        for req in history where req.httpMethod != "GET" {
            #expect(req.value(forHTTPHeaderField: "X-AxeForge") == "1")
        }

        // Verify translated tuning body sent to POST /api/settings
        let lastReq = try #require(history.last)
        #expect(lastReq.httpMethod == "POST")
        #expect(lastReq.url?.path == "/api/settings")
        let lastJSON = try JSONDecoder().decode(JSONValue.self, from: try #require(lastReq.httpBody))
        #expect(lastJSON["freq"]?.intValue == 650)
        #expect(lastJSON["mv"]?.intValue == 1200)
        #expect(lastJSON["atune"]?.boolValue == false)
    }

    @Test("Canaan Avalon cgminer write operations dispatch ascset commands over port 4028")
    func canaanAvalonAscsetWrites() async throws {
        final class CommandLog: @unchecked Sendable {
            let lock = NSLock()
            var payloads: [String] = []
            func append(_ s: String) { lock.withLock { payloads.append(s) } }
            func all() -> [String] { lock.withLock { payloads } }
        }
        let log = CommandLog()

        let transport: CgminerClient.Transport = { _, _, _, payload in
            log.append(String(data: payload, encoding: .utf8) ?? "")
            return Data(#"{"STATUS":[{"STATUS":"S","Code":118,"Msg":"ASC 0 set OK"}]}"#.utf8)
        }

        let device = MinerDevice(name: "Avalon Nano3s", address: "192.168.1.70:4028", firmwareFamily: "canaan")
        let adapter = MinerFirmwareAdapter(device: device, cgminerTransport: transport)

        #expect(try await adapter.setFanSpeed(65))
        #expect(try await adapter.setFanSpeed(10)) // < 15 switches to auto fan (-1)
        #expect(try await adapter.setFrequency(500))
        #expect(try await adapter.setVoltage(1150))
        #expect(try await adapter.setWorkmode(2))
        #expect(!(try await adapter.setWorkmode(5))) // invalid mode rejected before network
        #expect(try await adapter.restart())

        // Also test unified execute(.settings) on Canaan
        let settingsData = try JSONEncoder().encode(
            JSONValue.object(["frequency": .number(550), "manualFanSpeed": .integer(80), "autofanspeed": .integer(0)])
        )
        _ = try await adapter.execute(.settings, body: settingsData)

        let commands = log.all()
        #expect(commands.count == 8)
        #expect(commands[0].contains(#""parameter":"0,fan-spd,65""#))
        #expect(commands[1].contains(#""parameter":"0,fan-spd,-1""#))
        #expect(commands[2].contains(#""parameter":"0,frequency,500:500:500:500-0-0-0""#))
        #expect(commands[3].contains(#""parameter":"0,voltage,1150""#))
        #expect(commands[4].contains(#""parameter":"0,workmode,set,2""#))
        #expect(commands[5].contains(#""parameter":"0,reboot,0""#))
        #expect(commands[6].contains(#""parameter":"0,frequency,550:550:550:550-0-0-0""#))
        #expect(commands[7].contains(#""parameter":"0,fan-spd,80""#))
    }

    private static let sampleHarloInfoJSON = Data(#"""
    {
      "firmware": "Harlo-OS-V2",
      "firmware_version": "0.2.101",
      "fleet_api_version": 1,
      "macAddr": "02:11:22:33:44:55",
      "profile": {
        "id": "harlo-b30",
        "name": "Harlo B30",
        "algorithm": "sha256d",
        "asic_count": 6,
        "frequency_min_mhz": 400,
        "frequency_max_mhz": 800,
        "stock_frequency_mhz": 550,
        "core_min_mv": 1100,
        "core_max_mv": 1350,
        "stock_core_mv": 1200,
        "fan_channels": 2
      }
    }
    """#.utf8)

    private static let sampleHarloTelemetryJSON = Data(#"""
    {
      "miner_name": "harlo-b30-rack",
      "firmware_version": "0.2.101",
      "hashrate_ghs": 30250.0,
      "device_power_w": 432.5,
      "asic_temp_c": 57.5,
      "vr_temp_c": 63.0,
      "target_frequency_mhz": 600,
      "active_pll_mhz": 598.5,
      "target_core_mv": 1210,
      "core_voltage_mv": 1205,
      "input_voltage_v": 12.15,
      "asic_regulator_input_current_a": 35.6,
      "uptime_seconds": 86400,
      "asic_paused": false,
      "internal_heap_free_bytes": 184320,
      "best_share_session": 250000000,
      "best_share_all_time": 1250000000,
      "pool_difficulty": 4096,
      "pool_latency_ms": 24.5,
      "fans": [
        {"channel": 1, "mode": "auto", "percent": 68, "manual_percent": 70, "rpm": 4300, "target_c": 58, "sensor": "asic"},
        {"channel": 2, "mode": "auto", "percent": 64, "manual_percent": 70, "rpm": 4100, "target_c": 58, "sensor": "asic"}
      ],
      "pools": [
        {
          "slot": 1,
          "host": "us-east.harlolabs.com",
          "port": 8888,
          "user": "bitcoincash:qpztest.b30",
          "connected": true,
          "active_endpoint": "primary",
          "accepted_shares": 512,
          "rejected_shares": 3,
          "blocks_mined": 0,
          "latency_ms": 24.5
        }
      ]
    }
    """#.utf8)

    @Test("Harlo-OS (Harlo-OS-V2) discovery and telemetry read")
    func harloOSDiscoveryAndTelemetryRead() async throws {
        let detected = await MinerFirmwareAdapter.identifyHost(
            "192.168.1.80",
            httpTransport: { req in
                let path = req.url?.path ?? ""
                let resp = HTTPURLResponse(
                    url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                if path == "/api/info" { return (Self.sampleHarloInfoJSON, resp) }
                if path == "/api/telemetry" { return (Self.sampleHarloTelemetryJSON, resp) }
                let notFound = HTTPURLResponse(
                    url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil
                )!
                return (Data(), notFound)
            }
        )
        #expect(detected?.family == "harloOS")
        #expect(detected?.model == "Harlo B30")
        #expect(detected?.name == "harlo-b30-rack")
        #expect(detected?.mac == "02:11:22:33:44:55")
        let info = try #require(detected?.info)
        #expect(info.hashRate == 30250.0)
        #expect(info.power == 432.5)
        #expect(info.temp == 57.5)
        #expect(info.vrTemp == 63.0)
        #expect(info.frequency == 600.0)
        #expect(info.coreVoltage == 1210.0)
        #expect(info.coreVoltageActual == 1205.0)
        #expect(info.voltage == 12150.0)
        #expect(info.fanRpm == 4300.0)
        #expect(info.fan2Rpm == 4100.0)
        #expect(info.fanSpeed == 68.0)
        #expect(info.sharesAccepted == 512)
        #expect(info.sharesRejected == 3)
        #expect(info.poolURL == "us-east.harlolabs.com")
        #expect(info.raw["autofanspeed"]?.intValue == 1)
        #expect(info.raw["temptarget"]?.intValue == 58)
        #expect(MinerShapeValidator.isValidInfoShape(.object(info.raw)))
    }

    @Test("Harlo-OS (Harlo-OS-V2) write operations and endpoint translation")
    func harloOSWriteOperationsAndEndpointTranslation() async throws {
        let id = UUID().uuidString
        let session = makeSession(id: id) { req in
            if req.url?.path == "/api/telemetry" { return (200, Self.sampleHarloTelemetryJSON) }
            if req.url?.path == "/api/info" { return (200, Self.sampleHarloInfoJSON) }
            if req.url?.path == "/api/pools" && req.httpMethod == "GET" {
                let poolsBody = Data(#"""
                {"pools":[{"slot":1,"host":"us-east.harlolabs.com","port":8888,"user":"w1","backup":{"host":"pool.harlolabs.com","port":8888,"user":"w1"}}]}
                """#.utf8)
                return (200, poolsBody)
            }
            return (200, Data(#"{"ok":true,"output":"Saved on miner."}"#.utf8))
        }
        defer { session.invalidateAndCancel() }

        let device = MinerDevice(name: "Harlo B30", address: "192.168.1.80", firmwareFamily: "harloOS")
        let adapter = MinerFirmwareAdapter(device: device, session: session)

        // Setting frequency alone reads current target_core_mv (1210) from /api/telemetry and sends PUT /api/tuning
        #expect(try await adapter.setFrequency(650))
        #expect(try await adapter.setFanSpeed(85))
        #expect(try await adapter.setAutoFan(true))
        #expect(try await adapter.pause())
        #expect(try await adapter.resume())
        #expect(try await adapter.restart())

        let poolCfg = try await adapter.readPoolConfig()
        #expect(poolCfg.url == "us-east.harlolabs.com")
        #expect(poolCfg.port == 8888)
        #expect(poolCfg.fbURL == "pool.harlolabs.com")

        // Unified execute(.settings) with both frequency & coreVoltage + hostname
        let settingsPayload = try JSONEncoder().encode(
            JSONValue.object([
                "frequency": .number(675),
                "coreVoltage": .integer(1230),
                "hostname": .string("harlo-b30-turbo")
            ])
        )
        _ = try await adapter.execute(.settings, body: settingsPayload)

        let writes = sharedWriteRecorder.history(id: id).filter { $0.httpMethod != "GET" }
        #expect(writes.count == 8)
        #expect(writes[0].httpMethod == "PUT" && writes[0].url?.path == "/api/tuning")
        let tune0 = try JSONDecoder().decode(JSONValue.self, from: try #require(writes[0].httpBody))
        #expect(tune0["frequency_mhz"]?.intValue == 650 && tune0["core_mv"]?.intValue == 1210)

        #expect(writes[1].httpMethod == "PUT" && writes[1].url?.path == "/api/fans/1")
        let fan1 = try JSONDecoder().decode(JSONValue.self, from: try #require(writes[1].httpBody))
        #expect(fan1["mode"]?.stringValue == "manual" && fan1["percent"]?.intValue == 85)

        #expect(writes[2].httpMethod == "PUT" && writes[2].url?.path == "/api/fans/1")
        let fanAuto = try JSONDecoder().decode(JSONValue.self, from: try #require(writes[2].httpBody))
        #expect(fanAuto["mode"]?.stringValue == "auto" && fanAuto["sensor"]?.stringValue == "asic")

        #expect(writes[3].httpMethod == "POST" && writes[3].url?.path == "/api/asic/stop")
        #expect(writes[4].httpMethod == "POST" && writes[4].url?.path == "/api/asic/start")
        #expect(writes[5].httpMethod == "POST" && writes[5].url?.path == "/api/reboot")
        #expect(writes[6].httpMethod == "PUT" && writes[6].url?.path == "/api/tuning")
        #expect(writes[7].httpMethod == "PUT" && writes[7].url?.path == "/api/miner-name")
    }

    @Test("WarpAxe detection overrides underlying board slug and routes pause/resume to /api/v1/chips/*")
    func warpAxeDetectionAndWriteTranslation() async throws {
        // WarpAxe reports deviceModel/boardVersion as the underlying board slug (e.g. "bitaxe-gamma-duo"
        // or "nerdqaxe-plusplus"), while version is "warpaxe 0.1.47".
        let warpRaw: [String: JSONValue] = [
            "hostname": .string("warpaxe-lab"),
            "version": .string("warpaxe 0.1.47"),
            "boardName": .string("Bitaxe Gamma Duo"),
            "boardVersion": .string("bitaxe-gamma-duo"),
            "deviceModel": .string("bitaxe-gamma-duo"),
            "ASICModel": .string("BM1370"),
            "asicCount": .integer(2),
            "hashRate": .number(1980.0),
            "power": .number(28.5),
            "temp": .number(48.0),
            "dieTempC": .number(59.0),
            "frequency": .number(525),
            "frequencyActual": .number(525),
            "coreVoltage": .integer(1150),
            "coreVoltageActual": .integer(1199),
            "coreCurrentA": .number(3.0),
            "shutdown": .bool(false)
        ]

        #expect(MinerFirmwareAdapter.classifyAxeOSPayload(raw: warpRaw) == "warpAxe")
        let sample = MinerHTTPDrivers.parseWarpAxe(data: warpRaw, host: "127.0.0.1")
        #expect(sample.family == "warpAxe")
        #expect(sample.model == "Bitaxe Gamma Duo")
        #expect(sample.currentA == 3.0)
        #expect(sample.miningPaused == false)
        let info = sample.toMinerInfo(preservingFlatRaw: true)
        #expect(MinerFirmwareAdapter.detectedFamily(from: info) == "warpAxe")

        let id = UUID().uuidString
        let session = makeSession(id: id) { _ in (200, Data(#"{"ok":true}"#.utf8)) }
        defer { session.invalidateAndCancel() }

        let device = MinerDevice(name: "Warp Duo", address: "127.0.0.1:18182", firmwareFamily: "warpAxe")
        let adapter = MinerFirmwareAdapter(device: device, session: session)
        #expect(adapter.capabilities.canPause)
        #expect(adapter.capabilities.canShutdown)
        #expect(!adapter.capabilities.canIdentify)

        #expect(try await adapter.pause())
        #expect(try await adapter.resume())
        _ = try await adapter.execute(.pause)
        _ = try await adapter.execute(.resume)

        let reqs = sharedWriteRecorder.history(id: id)
        #expect(reqs.count == 4)
        #expect(reqs[0].httpMethod == "POST" && reqs[0].url?.path == "/api/v1/chips/off")
        #expect(reqs[1].httpMethod == "POST" && reqs[1].url?.path == "/api/v1/chips/on")
        #expect(reqs[2].httpMethod == "POST" && reqs[2].url?.path == "/api/v1/chips/off")
        #expect(reqs[3].httpMethod == "POST" && reqs[3].url?.path == "/api/v1/chips/on")
    }

    @Test("NerdQAxe identify is GET /api/v2/identify; BS-1 routes pause/resume like NerdQAxe")
    func nerdFamilyUpstreamRoutes() async throws {
        let id = UUID().uuidString
        let session = makeSession(id: id)
        defer { session.invalidateAndCancel() }

        let nerd = MinerFirmwareAdapter(
            device: MinerDevice(name: "NQ", address: "192.168.1.70", firmwareFamily: "nerdqaxe"),
            session: session
        )
        #expect(try await nerd.identify())

        let bs1 = MinerFirmwareAdapter(
            device: MinerDevice(name: "BS-1", address: "192.168.1.71", firmwareFamily: "bitfortun"),
            session: session
        )
        #expect(try await bs1.pause())
        #expect(try await bs1.resume())
        #expect(try await bs1.identify() == false)
        let caps = MinerDriverCapabilities.forFamily("bitfortun")
        #expect(!caps.canPause && caps.canShutdown && !caps.canIdentify)

        let body = try JSONEncoder().encode(JSONValue.object(["temptarget": .integer(60)]))
        _ = try await bs1.execute(.settings, body: body)

        let reqs = sharedWriteRecorder.history(id: id)
        #expect(reqs.count == 4)
        #expect(reqs[0].httpMethod == "GET" && reqs[0].url?.path == "/api/v2/identify")
        #expect(reqs[1].httpMethod == "POST" && reqs[1].url?.path == "/api/system/shutdown")
        #expect(reqs[2].httpMethod == "POST" && reqs[2].url?.path == "/api/system/restart")
        #expect(reqs[3].httpMethod == "PATCH" && reqs[3].url?.path == "/api/system")
        let sent = try JSONDecoder().decode(JSONValue.self, from: reqs[3].httpBody ?? Data())
        guard case .object(let dict) = sent else { Issue.record("body not object"); return }
        #expect(dict["temptarget"] == nil)
        #expect(dict["pidTargetTemp"] == .integer(60))
    }

    @Test("BitForge manual fan write forces autofanspeed:0 like MinerWatch")
    func bitForgeFanForcesManualMode() throws {
        let body = try JSONEncoder().encode(JSONValue.object(["manualFanSpeed": .integer(55)]))
        let out = try #require(MinerFirmwareAdapter.translateBitForgeSettingsBody(body))
        let json = try JSONDecoder().decode(JSONValue.self, from: out)
        guard case .object(let dict) = json else { Issue.record("not object"); return }
        #expect(dict["fanspeed"] == .integer(55))
        #expect(dict["autofanspeed"] == .integer(0))
    }

    @Test("WarpAxe settings use its Config field names (fanspeed, pidTargetTemp)")
    func warpAxeSettingsKeys() throws {
        let body = try JSONEncoder().encode(JSONValue.object([
            "manualFanSpeed": .integer(70), "temptarget": .integer(62), "frequency": .integer(500)
        ]))
        let out = try #require(MinerFirmwareAdapter.translateWarpAxeSettingsBody(body))
        guard case .object(let dict) = try JSONDecoder().decode(JSONValue.self, from: out) else {
            Issue.record("not object"); return
        }
        #expect(dict["fanspeed"] == .integer(70))
        #expect(dict["pidTargetTemp"] == .integer(62))
        #expect(dict["frequency"] == .integer(500))
        #expect(dict["manualFanSpeed"] == nil && dict["temptarget"] == nil)
    }
}
