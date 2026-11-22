import Foundation
import Network

/// An in-process HTTP fixture, reachable only through IPv4 loopback.
/// The app under UI test still uses its real URLSession and request encoder.
final class LoopbackMinerServer: @unchecked Sendable {
    struct Request: Sendable {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    enum ServerError: LocalizedError {
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .failed(let message): message
            }
        }
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "app.hashfleet.uitests.loopback-miner")
    private let lock = NSLock()
    private let started = DispatchSemaphore(value: 0)
    // Every mutable property below is protected by lock, including cross-process test reads.
    private var requests: [Request] = []
    private var fixtureHostname = "loopback-before"
    private var fixtureASICStatus = 404
    private var fixtureASICBody = Data("{}".utf8)
    private var fixtureInfoResponse: (status: Int, body: Data)?
    private var poolWriteReadback: Data?
    private var fixtureInfoDelay: TimeInterval = 0
    private var holdsNextInfoRead = false
    private var pendingInfoRead: NWConnection?
    private var tuningWritesEnabled = false
    private var tuningReadbackMatches = true
    private var fixtureFrequency = 500
    private var fixtureCoreVoltage = 1150
    private var fixtureCooling: [String: Int]?
    private var pendingCoolingWrite: (connection: NWConnection, fields: [String: Int])?
    private var fixtureDisplay: [String: Int]?
    private var pendingDisplayWrite: (connection: NWConnection, fields: [String: Int])?
    private var fixturePaused: Bool?
    private var pendingMiningAction: (connection: NWConnection, paused: Bool)?
    private var servesWebPage = false
    private var boundPort: UInt16?
    private var startupFailure: String?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var didStart = false

    var journal: [Request] { lock.withLock { requests } }
    var writes: [Request] { journal.filter { ["PATCH", "POST", "PUT", "DELETE"].contains($0.method) } }
    var hostname: String { lock.withLock { fixtureHostname } }

    func enableWebPage() { lock.withLock { servesWebPage = true } }

    func setASICResponse(status: Int, json: String) {
        lock.withLock {
            fixtureASICStatus = status
            fixtureASICBody = Data(json.utf8)
        }
    }

    /// Faults and partial telemetry are served only by this loopback test server.
    func setInfoResponse(status: Int, json: String) {
        lock.withLock { fixtureInfoResponse = (status, Data(json.utf8)) }
    }

    /// A pool write is opt-in and observable only on this IPv4 loopback fixture.
    func acceptPoolWrite(readbackJSON: String) {
        lock.withLock { poolWriteReadback = Data(readbackJSON.utf8) }
    }

    /// Bounded delay for first-load skeleton acceptance. Never affects real miner traffic.
    func setInfoDelay(_ seconds: TimeInterval) {
        lock.withLock { fixtureInfoDelay = max(0, min(seconds, 6)) }
    }

    func holdNextInfoRead() { lock.withLock { holdsNextInfoRead = true } }
    var hasPendingInfoRead: Bool { lock.withLock { pendingInfoRead != nil } }

    @discardableResult func finishInfoRead(status: Int, json: String) -> Bool {
        let pending = lock.withLock {
            let pending = pendingInfoRead
            pendingInfoRead = nil
            return pending
        }
        guard let pending else { return false }
        respond(pending, status: status, body: Data(json.utf8))
        return true
    }

    /// Opt-in for tuning acceptance only. Still bound exclusively to 127.0.0.1.
    func enableTuningWrites(readbackMatches: Bool = true) {
        lock.withLock {
            tuningWritesEnabled = true
            tuningReadbackMatches = readbackMatches
        }
    }

    /// Hold a valid PATCH response until the test has inspected the in-flight button.
    func holdCoolingWrites() {
        lock.withLock { fixtureCooling = ["autofanspeed": 1, "manualFanSpeed": 65, "temptarget": 66, "minFanSpeed": 25] }
    }

    var hasPendingCoolingWrite: Bool { lock.withLock { pendingCoolingWrite != nil } }

    @discardableResult func finishCoolingWrite(accept: Bool = true) -> Bool {
        let pending = lock.withLock {
            let pending = pendingCoolingWrite
            if let pending, accept { fixtureCooling?.merge(pending.fields) { _, value in value } }
            pendingCoolingWrite = nil
            return pending
        }
        guard let pending else { return false }
        respond(pending.connection, status: accept ? 200 : 400, body: Data((accept
            ? #"{"status":"success"}"# : #"{"error":"Cooling settings rejected by fixture"}"#).utf8))
        return true
    }

    func holdDisplayWrites() {
        lock.withLock { fixtureDisplay = ["rotation": 0, "invertscreen": 0, "displayTimeout": 5] }
    }

    func holdMiningActions() { lock.withLock { fixturePaused = false } }

    var hasPendingMiningAction: Bool { lock.withLock { pendingMiningAction != nil } }

    @discardableResult func finishMiningAction(accept: Bool = true) -> Bool {
        let pending = lock.withLock {
            let pending = pendingMiningAction
            if let pending, accept { fixturePaused = pending.paused }
            pendingMiningAction = nil
            return pending
        }
        guard let pending else { return false }
        respond(pending.connection, status: accept ? 200 : 404,
                body: Data((accept ? #"{"status":"success"}"# : #"{"error":"Unsupported command"}"#).utf8))
        return true
    }

    var hasPendingDisplayWrite: Bool { lock.withLock { pendingDisplayWrite != nil } }

    @discardableResult func finishDisplayWrite(accept: Bool = true) -> Bool {
        let pending = lock.withLock {
            let pending = pendingDisplayWrite
            if let pending, accept { fixtureDisplay?.merge(pending.fields) { _, value in value } }
            pendingDisplayWrite = nil
            return pending
        }
        guard let pending else { return false }
        respond(pending.connection, status: accept ? 200 : 400, body: Data((accept
            ? #"{"status":"success"}"# : #"{"error":"Display settings rejected by fixture"}"#).utf8))
        return true
    }

    init() throws {
        let parameters = NWParameters.tcp
        // Do not replace this with an unspecified/wildcard host. UI tests must
        // never expose a write-capable mock to the LAN or a physical miner.
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(IPv4Address("127.0.0.1")!), port: .any)
        parameters.includePeerToPeer = false
        parameters.allowLocalEndpointReuse = false
        listener = try NWListener(using: parameters)
    }

    /// Returns the loopback address after NWListener has actually bound its ephemeral port.
    func start() throws -> String {
        let firstStart = lock.withLock {
            guard !didStart else { return false }
            didStart = true
            return true
        }
        guard firstStart else { throw ServerError.failed("The loopback fixture can only be started once.") }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.lock.withLock { self.boundPort = self.listener.port?.rawValue }
                self.started.signal()
            case .failed(let error):
                self.lock.withLock { self.startupFailure = error.localizedDescription }
                self.started.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            self.accept(connection)
        }
        listener.start(queue: queue)
        guard started.wait(timeout: .now() + 5) == .success else {
            stop()
            throw ServerError.failed("Timed out starting the IPv4 loopback fixture.")
        }
        let result = lock.withLock { (boundPort, startupFailure) }
        guard let port = result.0, port != 0, result.1 == nil else {
            stop()
            throw ServerError.failed(result.1 ?? "Loopback fixture did not bind an ephemeral port.")
        }
        return "127.0.0.1:\(port)"
    }

    func stop() {
        listener.cancel()
        let active = lock.withLock {
            let active = Array(connections.values)
            connections.removeAll()
            pendingInfoRead = nil
            pendingCoolingWrite = nil
            pendingDisplayWrite = nil
            pendingMiningAction = nil
            return active
        }
        active.forEach { $0.cancel() }
    }

    private func accept(_ connection: NWConnection) {
        lock.withLock { connections[ObjectIdentifier(connection)] = connection }
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .cancelled, .failed:
                self.lock.withLock { _ = self.connections.removeValue(forKey: ObjectIdentifier(connection)) }
            default: break
            }
        }
        connection.start(queue: queue)
        receive(connection, accumulated: Data())
        queue.asyncAfter(deadline: .now() + 10) { [weak connection] in connection?.cancel() }
    }

    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 64 * 1_024
        ) { [weak self, connection] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var buffer = accumulated
            if let data { buffer.append(data) }
            guard error == nil, buffer.count <= 288 * 1_024 else {
                connection.cancel()
                return
            }
            let separator = Data("\r\n\r\n".utf8)
            guard let range = buffer.range(of: separator) else {
                guard !isComplete, buffer.count <= 32 * 1_024 else { connection.cancel(); return }
                self.receive(connection, accumulated: buffer)
                return
            }
            guard range.lowerBound <= 32 * 1_024,
                  let text = String(data: buffer[..<range.lowerBound], encoding: .utf8),
                  let header = self.parseHeaders(text) else {
                self.respond(connection, status: 400, body: Data(#"{"error":"Malformed fixture request"}"#.utf8))
                return
            }
            let bodyStart = range.upperBound
            guard buffer.count - bodyStart >= header.length else {
                guard !isComplete else { connection.cancel(); return }
                self.receive(connection, accumulated: buffer)
                return
            }
            let body = Data(buffer[bodyStart..<(bodyStart + header.length)])
            let request = Request(method: header.method, path: header.path, headers: header.fields, body: body)
            let delay = request.method == "GET" && request.path == "/api/system/info"
                ? self.lock.withLock { self.fixtureInfoDelay } : 0
            if delay > 0 {
                self.queue.asyncAfter(deadline: .now() + delay) { [weak self, weak connection] in
                    guard let self, let connection else { return }
                    self.handle(request, connection: connection)
                }
            } else {
                self.handle(request, connection: connection)
            }
        }
    }

    private struct ParsedHeaders {
        let method: String
        let path: String
        let fields: [String: String]
        let length: Int
    }

    private func parseHeaders(_ text: String) -> ParsedHeaders? {
        let lines = text.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let parts = first.split(separator: " ")
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1."), parts[1].hasPrefix("/") else { return nil }
        var fields: [String: String] = [:]
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { return nil }
            let key = pair[0].trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty, fields[key] == nil else { return nil }
            fields[key] = pair[1].trimmingCharacters(in: .whitespaces)
        }
        // URLSession's Data-backed requests use Content-Length. Reject chunked
        // framing instead of accidentally counting a partial or ambiguous write.
        guard fields["transfer-encoding"] == nil,
              let length = Int(fields["content-length"] ?? "0"),
              (0...(256 * 1_024)).contains(length)
        else { return nil }
        let path = String(parts[1].split(separator: "?", maxSplits: 1)[0])
        return ParsedHeaders(method: String(parts[0]), path: path, fields: fields, length: length)
    }

    private func handle(_ request: Request, connection: NWConnection) {
        lock.withLock { requests.append(request) }
        if request.method == "GET", request.path == "/", lock.withLock({ servesWebPage }) {
            let page = "<!doctype html><meta name='viewport' content='width=device-width'><h1>Loopback miner web interface</h1>"
            respond(connection, status: 200, body: Data(page.utf8), contentType: "text/html; charset=utf-8")
        } else if request.method == "GET", request.path == "/api/system/info" {
            handleInfo(connection: connection)
        } else if request.method == "GET", request.path == "/api/system/asic" {
            let response = lock.withLock { (fixtureASICStatus, fixtureASICBody) }
            respond(connection, status: response.0, body: response.1)
        } else if request.method == "POST", request.body.isEmpty,
                  ["/api/system/pause", "/api/system/resume"].contains(request.path) {
            if lock.withLock({ fixturePaused != nil }) {
                let held = lock.withLock {
                    guard pendingMiningAction == nil else { return false }
                    pendingMiningAction = (connection, request.path == "/api/system/pause")
                    return true
                }
                if !held { respond(connection, status: 400, body: Data(#"{"error":"Duplicate command"}"#.utf8)) }
            } else if request.path == "/api/system/pause" {
                respond(connection, status: 200, body: Data(#"{"status":"success"}"#.utf8))
            } else {
                respond(connection, status: 404, body: Data(#"{"error":"Unsupported command"}"#.utf8))
            }
        } else if request.method == "POST", request.path == "/api/system/restart", request.body.isEmpty,
                  lock.withLock({ fixtureDisplay != nil }) {
            respond(connection, status: 200, body: Data(#"{"status":"success"}"#.utf8))
        } else if request.method == "PATCH", request.path == "/api/system" {
            handlePatch(request, connection: connection)
        } else {
            respond(connection, status: 404, body: Data(#"{"error":"Endpoint unsupported by loopback fixture"}"#.utf8))
        }
    }

    private func handleInfo(connection: NWConnection) {
        let held = lock.withLock {
            guard holdsNextInfoRead, pendingInfoRead == nil else { return false }
            holdsNextInfoRead = false
            pendingInfoRead = connection
            return true
        }
        guard !held else { return }
        if let response = lock.withLock({ fixtureInfoResponse }) {
            respond(connection, status: response.status, body: response.body)
            return
        }
        let setpoints = lock.withLock { (fixtureFrequency, fixtureCoreVoltage) }
        var info: [String: Any] = [
            "hostname": hostname, "version": "ui-loopback-fixture", "ASICModel": "BM1370",
            "hashRate": 1234, "power": 19.5, "temp": 51, "vrTemp": 48,
            "fanspeed": 65, "fanrpm": 4200, "voltage": 5000, "coreVoltage": setpoints.1,
            "frequency": setpoints.0, "sharesAccepted": 24, "sharesRejected": 0,
            "uptimeSeconds": 1200, "bestDiff": "42M", "wifiRSSI": -45,
            "stratumURL": "pool.fixture.invalid", "autofanspeed": 1, "manualFanSpeed": 65,
            "temptarget": 66, "primaryPoolIndex": 0, "secondaryPoolIndex": 1, "pools": []
        ]
        if let cooling = lock.withLock({ fixtureCooling }) {
            info["macAddr"] = "02:00:00:00:00:01"
            for (key, value) in cooling { info[key] = value }
        }
        if let display = lock.withLock({ fixtureDisplay }) {
            info["macAddr"] = "02:00:00:00:00:01"
            for (key, value) in display { info[key] = value }
        }
        if let paused = lock.withLock({ fixturePaused }) {
            info["macAddr"] = "02:00:00:00:00:01"
            info["miningPaused"] = paused
        }
        do {
            let body = try JSONSerialization.data(withJSONObject: info, options: [.sortedKeys])
            respond(connection, status: 200, body: body)
        } catch {
            respond(connection, status: 500, body: Data("{}".utf8))
        }
    }

    private func handlePatch(_ request: Request, connection: NWConnection) {
        if let readback = lock.withLock({ poolWriteReadback }),
           let fields = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
           fields.count == 1, let pools = fields["pools"] as? [[String: Any]], pools.count == 1 {
            lock.withLock { fixtureInfoResponse = (200, readback) }
            respond(connection, status: 200, body: Data(#"{"status":"success"}"#.utf8))
            return
        }
        if let display = lock.withLock({ fixtureDisplay }) {
            let accepted = lock.withLock {
                guard pendingDisplayWrite == nil,
                      let fields = try? JSONSerialization.jsonObject(with: request.body) as? [String: Int],
                      fields.count == 1, fields.keys.allSatisfy({ display[$0] != nil }) else { return false }
                pendingDisplayWrite = (connection, fields)
                return true
            }
            if !accepted { respond(connection, status: 400, body: Data(#"{"error":"Invalid fixture display payload"}"#.utf8)) }
            return
        }
        if let cooling = lock.withLock({ fixtureCooling }) {
            let accepted = lock.withLock {
                guard pendingCoolingWrite == nil,
                      let fields = try? JSONSerialization.jsonObject(with: request.body) as? [String: Int],
                      !fields.isEmpty, Set(fields.keys).isSubset(of: Set(cooling.keys)) else { return false }
                pendingCoolingWrite = (connection, fields)
                return true
            }
            if !accepted { respond(connection, status: 400, body: Data(#"{"error":"Invalid fixture cooling payload"}"#.utf8)) }
            return
        }
        if lock.withLock({ tuningWritesEnabled }) {
            handleTuning(request, connection: connection)
            return
        }
        guard let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
              let hostname = object["hostname"] as? String, !hostname.isEmpty else {
            respond(connection, status: 400, body: Data(#"{"error":"Fixture PATCH requires hostname"}"#.utf8))
            return
        }
        lock.withLock { fixtureHostname = hostname }
        let message = #"{"status":"success","message":"Loopback hostname updated"}"#
        respond(connection, status: 200, body: Data(message.utf8))
    }

    private func handleTuning(_ request: Request, connection: NWConnection) {
        guard let fields = try? JSONSerialization.jsonObject(with: request.body) as? [String: Int],
            !fields.isEmpty, Set(fields.keys).isSubset(of: ["frequency", "coreVoltage"])
        else {
            respond(connection, status: 400, body: Data(#"{"error":"Invalid fixture tuning payload"}"#.utf8))
            return
        }
        lock.withLock {
            guard tuningReadbackMatches else { return }
            if let frequency = fields["frequency"] { fixtureFrequency = frequency }
            if let voltage = fields["coreVoltage"] { fixtureCoreVoltage = voltage }
        }
        respond(connection, status: 200, body: Data(#"{"status":"success"}"#.utf8))
    }

    private func respond(_ connection: NWConnection, status: Int, body: Data, contentType: String = "application/json") {
        let reason = [200: "OK", 400: "Bad Request", 404: "Not Found", 500: "Internal Server Error"][status] ?? "Error"
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\n"
            + "Content-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n"
        var response = Data(head.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}
