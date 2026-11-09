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
    private var fixtureInfoDelay: TimeInterval = 0
    private var tuningWritesEnabled = false
    private var tuningReadbackMatches = true
    private var fixtureFrequency = 500
    private var fixtureCoreVoltage = 1150
    private var boundPort: UInt16?
    private var startupFailure: String?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var didStart = false

    var journal: [Request] { lock.withLock { requests } }
    var writes: [Request] { journal.filter { ["PATCH", "POST", "PUT", "DELETE"].contains($0.method) } }
    var hostname: String { lock.withLock { fixtureHostname } }

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

    /// Bounded delay for first-load skeleton acceptance. Never affects real miner traffic.
    func setInfoDelay(_ seconds: TimeInterval) {
        lock.withLock { fixtureInfoDelay = max(0, min(seconds, 6)) }
    }

    /// Opt-in for tuning acceptance only. Still bound exclusively to 127.0.0.1.
    func enableTuningWrites(readbackMatches: Bool = true) {
        lock.withLock {
            tuningWritesEnabled = true
            tuningReadbackMatches = readbackMatches
        }
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
        if request.method == "GET", request.path == "/api/system/info" {
            if let response = lock.withLock({ fixtureInfoResponse }) {
                respond(connection, status: response.status, body: response.body)
                return
            }
            let setpoints = lock.withLock { (fixtureFrequency, fixtureCoreVoltage) }
            let info: [String: Any] = [
                "hostname": hostname, "version": "ui-loopback-fixture", "ASICModel": "BM1370",
                "hashRate": 1234, "power": 19.5, "temp": 51, "vrTemp": 48,
                "fanspeed": 65, "fanrpm": 4200, "voltage": 5000, "coreVoltage": setpoints.1,
                "frequency": setpoints.0, "sharesAccepted": 24, "sharesRejected": 0,
                "uptimeSeconds": 1200, "bestDiff": "42M", "wifiRSSI": -45,
                "stratumURL": "pool.fixture.invalid", "autofanspeed": 1, "manualFanSpeed": 65,
                "temptarget": 66, "primaryPoolIndex": 0, "secondaryPoolIndex": 1, "pools": []
            ]
            do {
                let body = try JSONSerialization.data(withJSONObject: info, options: [.sortedKeys])
                respond(connection, status: 200, body: body)
            } catch {
                respond(connection, status: 500, body: Data("{}".utf8))
            }
        } else if request.method == "GET", request.path == "/api/system/asic" {
            let response = lock.withLock { (fixtureASICStatus, fixtureASICBody) }
            respond(connection, status: response.0, body: response.1)
        } else if request.method == "PATCH", request.path == "/api/system" {
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
        } else {
            respond(connection, status: 404, body: Data(#"{"error":"Endpoint unsupported by loopback fixture"}"#.utf8))
        }
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

    private func respond(_ connection: NWConnection, status: Int, body: Data) {
        let reason = [200: "OK", 400: "Bad Request", 404: "Not Found", 500: "Internal Server Error"][status] ?? "Error"
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\n"
            + "Content-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n"
        var response = Data(head.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}
