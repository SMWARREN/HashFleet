import Foundation
import Testing
@testable import HashFleetCore

/// Independently transcribed from ESP-Miner 2943d206's http_server.c and theme_api.c.
/// Do not derive this fixture from MinerEndpoint.catalog: doing so hides missing routes.
struct FirmwareOperation: Sendable {
    let endpoint: MinerEndpoint
    let method: String
    let path: String
    let contentType: String?
    let timeout: TimeInterval
    let webSocket: Bool

    init(_ endpoint: MinerEndpoint, _ method: String, _ path: String,
         contentType: String? = nil, timeout: TimeInterval = 15, webSocket: Bool = false) {
        self.endpoint = endpoint
        self.method = method
        self.path = path
        self.contentType = contentType
        self.timeout = timeout
        self.webSocket = webSocket
    }

    static let upstream: [Self] = [
        .init(.info, "GET", "/api/system/info"),
        .init(.asic, "GET", "/api/system/asic"),
        .init(.statistics, "GET", "/api/system/statistics"),
        .init(.scoreboard, "GET", "/api/system/scoreboard"),
        .init(.wifiScan, "GET", "/api/system/wifi/scan", timeout: 30),
        .init(.logs, "GET", "/api/system/logs"),
        .init(.identify, "POST", "/api/system/identify"),
        .init(.restart, "POST", "/api/system/restart"),
        .init(.pause, "POST", "/api/system/pause"),
        .init(.resume, "POST", "/api/system/resume"),
        .init(.dismissBlockFound, "POST", "/api/system/blockFound/dismiss"),
        .init(.settings, "PATCH", "/api/system", contentType: "application/json"),
        .init(.boot, "POST", "/api/system/boot", contentType: "application/json"),
        .init(.updatePool(0), "PUT", "/api/system/pools/0", contentType: "application/json"),
        .init(.deletePool(0), "DELETE", "/api/system/pools/0"),
        .init(.otaFirmware, "POST", "/api/system/OTA", contentType: "application/octet-stream", timeout: 300),
        .init(.otaWWW, "POST", "/api/system/OTAWWW", contentType: "application/octet-stream", timeout: 300),
        .init(.theme, "GET", "/api/theme"),
        .init(.updateTheme, "POST", "/api/theme", contentType: "application/json"),
        .init(.logWebSocket, "GET", "/api/ws", webSocket: true),
        .init(.liveWebSocket, "GET", "/api/ws/live", webSocket: true),
        .init(.recovery, "GET", "/recovery"),
        // /api/* is a firmware wildcard, not a literal URL to send.
        .init(.options, "OPTIONS", "/api/system/info")
    ]

    // readme.md still lists this route. It is NOT registered by audited master.
    static let legacy: [Self] = [
        .init(.dashboardStatistics, "GET", "/api/system/statistics/dashboard")
    ]

    static var supported: [Self] { upstream + legacy }
}

struct EndpointTests {
    private let client = MinerAPIClient(device: MinerDevice(name: "Offline", address: "miner.invalid:8080"))

    @Test func catalogCoversIndependentUpstreamInventoryExactlyOnce() {
        #expect(FirmwareOperation.upstream.count == 23)
        #expect(Set(MinerEndpoint.catalog) == Set(FirmwareOperation.supported.map(\.endpoint)))
        #expect(MinerEndpoint.catalog.count == 24)
        #expect(Set(MinerEndpoint.catalog.map(\.id)).count == 24)
        #expect(MinerEndpoint.dashboardStatistics.isLegacy)
        #expect(FirmwareOperation.upstream.allSatisfy { $0.endpoint.isLegacy == false })
        #expect(MinerEndpoint.allCases == MinerEndpoint.catalog)
        #expect(MinerEndpoint.catalog.allSatisfy { $0.title.isEmpty == false })
    }

    @Test(arguments: FirmwareOperation.supported)
    func methodsPathsTypesAndTimeoutsMatchFirmware(operation: FirmwareOperation) throws {
        let endpoint = operation.endpoint
        #expect(endpoint.path == operation.path)
        #expect(endpoint.method == operation.method)
        // Bodyless POST actions also advertise JSON if callers supply a body,
        // but the actual header must remain absent on the bodyless request below.
        let declaredType = operation.contentType ?? (operation.method == "POST" ? "application/json" : nil)
        #expect(endpoint.contentType == declaredType)
        #expect(endpoint.timeout == operation.timeout)
        #expect(endpoint.isWebSocket == operation.webSocket)
        let body = operation.contentType.map { _ in Data("payload".utf8) }
        let request = try client.request(for: endpoint, body: body)
        #expect(request.url?.path == operation.path)
        #expect(request.url?.host == "miner.invalid")
        #expect(request.url?.port == 8080)
        #expect(request.url?.scheme == (operation.webSocket ? "ws" : "http"))
        #expect(request.httpMethod == operation.method)
        #expect(request.timeoutInterval == operation.timeout)
        #expect(request.httpBody == body)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == operation.contentType)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Origin") == nil)
        #expect(request.httpShouldHandleCookies == false)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test(arguments: [MinerEndpoint.info, .asic, .statistics, .scoreboard, .wifiScan, .theme])
    func readRequestsAskForJSONWithoutBody(endpoint: MinerEndpoint) throws {
        let request = try client.request(for: endpoint)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
        #expect(request.httpBody == nil)
    }

    @Test(arguments: [MinerEndpoint.logs, .recovery, .otaFirmware, .otaWWW])
    func textAndBinaryEndpointsDoNotRequireJSONResponses(endpoint: MinerEndpoint) throws {
        let request = try client.request(for: endpoint)
        #expect(request.value(forHTTPHeaderField: "Accept") == "*/*")
    }

    @Test(arguments: Array(0...7))
    func everyPoolSlotHasBothMethods(index: Int) throws {
        let update = try client.request(for: .updatePool(index), body: Data("{}".utf8))
        let delete = try client.request(for: .deletePool(index))
        #expect(update.url?.path == "/api/system/pools/\(index)")
        #expect(delete.url?.path == update.url?.path)
        #expect(update.httpMethod == "PUT")
        #expect(delete.httpMethod == "DELETE")
        #expect(MinerEndpoint.updatePool(index).id != MinerEndpoint.deletePool(index).id)
    }

    @Test(arguments: [-1, 8, Int.min, Int.max])
    func invalidPoolSlotsAreRejectedAtRequestTime(index: Int) {
        for endpoint in [MinerEndpoint.updatePool(index), .deletePool(index)] {
            do {
                _ = try client.request(for: endpoint)
                Issue.record("Invalid pool slot accepted: \(index)")
            } catch MinerAPIError.invalidPoolIndex(let rejected) {
                #expect(rejected == index)
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test func queryItemsAreEncodedWithoutChangingTheRoute() throws {
        let items = [URLQueryItem(name: "columns", value: "hashrate,power"),
                     URLQueryItem(name: "note", value: "a&b=1 /? ü+#"),
                     URLQueryItem(name: "flag", value: nil),
                     URLQueryItem(name: "columns", value: "temp")]
        let request = try client.request(for: .statistics, query: items)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/api/system/statistics")
        #expect(components.queryItems == items)
        #expect(components.fragment == nil)
    }

    @Test(arguments: [MinerEndpoint.logWebSocket, .liveWebSocket])
    func secureBaseCreatesSecureWebSocketRequests(endpoint: MinerEndpoint) throws {
        let secure = MinerAPIClient(device: MinerDevice(name: "TLS", address: "https://[2001:db8::1]:8443"))
        let request = try secure.request(for: endpoint)
        #expect(request.url?.scheme == "wss")
        #expect(request.url?.port == 8443)
        #expect(request.url?.path == endpoint.path)
    }

    @Test func disruptiveOperationsAreMarkedForCallerConfirmation() {
        for endpoint in [MinerEndpoint.restart, .pause, .settings, .boot, .updatePool(0),
                         .deletePool(0), .otaFirmware, .otaWWW] {
            #expect(endpoint.isDestructive, "\(endpoint) requires deliberate user intent")
        }
        #expect(MinerEndpoint.info.isDestructive == false)
        #expect(MinerEndpoint.logs.isDestructive == false)
    }

    @Test(arguments: Array(0...7))
    func validPoolSlotsPassDirectValidation(index: Int) throws {
        try MinerEndpoint.updatePool(index).validate()
        try MinerEndpoint.deletePool(index).validate()
        #expect(MinerEndpoint.updatePool(index).title == "Update pool slot \(index)")
        #expect(MinerEndpoint.deletePool(index).title == "Delete pool slot \(index)")
        #expect(MinerEndpoint.updatePool(index).id == "PUT /api/system/pools/\(index)")
        #expect(MinerEndpoint.deletePool(index).id == "DELETE /api/system/pools/\(index)")
    }

    @Test(arguments: [-1, 8, -100, 100, Int.min, Int.max])
    func invalidPoolSlotsFailDirectValidation(index: Int) {
        for endpoint in [MinerEndpoint.updatePool(index), .deletePool(index)] {
            do {
                try endpoint.validate()
                Issue.record("Expected validate to throw for slot: \(index)")
            } catch MinerAPIError.invalidPoolIndex(let rejected) {
                #expect(rejected == index)
            } catch {
                Issue.record("Unexpected error from validate(): \(error)")
            }
        }
    }

    @Test func nonPoolEndpointsPassDirectValidation() throws {
        for endpoint in [
            MinerEndpoint.info, .asic, .statistics, .dashboardStatistics,
            .scoreboard, .wifiScan, .logs, .identify, .restart, .pause,
            .resume, .dismissBlockFound, .settings, .boot, .otaFirmware,
            .otaWWW, .theme, .updateTheme, .logWebSocket, .liveWebSocket,
            .recovery, .options
        ] {
            try endpoint.validate()
        }
    }

    @Test func endpointTitlesAndIdentifiersAreConsistent() {
        #expect(MinerEndpoint.info.title == "System info")
        #expect(MinerEndpoint.asic.title == "ASIC configuration")
        #expect(MinerEndpoint.statistics.title == "Statistics history")
        #expect(MinerEndpoint.dashboardStatistics.title == "Dashboard statistics (legacy firmware only)")
        #expect(MinerEndpoint.scoreboard.title == "Best-share scoreboard")
        #expect(MinerEndpoint.wifiScan.title == "Scan Wi-Fi networks")
        #expect(MinerEndpoint.logs.title == "Buffered logs")
        #expect(MinerEndpoint.identify.title == "Identify device")
        #expect(MinerEndpoint.restart.title == "Restart device")
        #expect(MinerEndpoint.pause.title == "Pause mining")
        #expect(MinerEndpoint.resume.title == "Resume mining")
        #expect(MinerEndpoint.dismissBlockFound.title == "Dismiss block-found alert")
        #expect(MinerEndpoint.settings.title == "Update settings")
        #expect(MinerEndpoint.boot.title == "Select boot partition")
        #expect(MinerEndpoint.otaFirmware.title == "Upload firmware")
        #expect(MinerEndpoint.otaWWW.title == "Upload web interface")
        #expect(MinerEndpoint.theme.title == "Read theme")
        #expect(MinerEndpoint.updateTheme.title == "Update theme")
        #expect(MinerEndpoint.logWebSocket.title == "Live logs (WebSocket)")
        #expect(MinerEndpoint.liveWebSocket.title == "Live telemetry (WebSocket)")
        #expect(MinerEndpoint.recovery.title == "Recovery page")
        #expect(MinerEndpoint.options.title == "API preflight capabilities")

        for endpoint in MinerEndpoint.catalog {
            #expect(endpoint.id == "\(endpoint.method) \(endpoint.path)")
            #expect(endpoint.isBinaryUpload == (endpoint == .otaFirmware || endpoint == .otaWWW))
        }
    }
}
