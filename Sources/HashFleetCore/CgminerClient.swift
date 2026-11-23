import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum CgminerError: Error, LocalizedError, Equatable, Sendable {
    case invalidHost(String)
    case connectionFailed(String)
    case timeout(String)
    case emptyResponse
    case unparseableResponse(String)

    public var errorDescription: String? {
        switch self {
        case .invalidHost(let host):
            "Invalid cgminer host '\(host)'."
        case .connectionFailed(let detail):
            "Could not connect to cgminer API: \(detail)"
        case .timeout(let host):
            "Timed out waiting for cgminer API on \(host)."
        case .emptyResponse:
            "The cgminer API returned an empty response."
        case .unparseableResponse(let preview):
            "The cgminer API returned an unrecognized response: \(preview)"
        }
    }
}

/// Request/response TCP client for cgminer-compatible firmware on port 4028
/// (Canaan Avalon, Braiins BOSminer/BMM101, Luxor LuxOS).
///
/// Supports both JSON responses and legacy pipe-delimited cgminer responses.
public struct CgminerClient: Sendable {
    public typealias Transport = @Sendable (String, Int, TimeInterval, Data) async throws -> Data

    public static let defaultPort = 4028
    public let host: String
    public let port: Int
    public let timeout: TimeInterval
    private let transport: Transport?

    public init(
        host: String,
        port: Int = CgminerClient.defaultPort,
        timeout: TimeInterval = 4.0,
        transport: Transport? = nil
    ) {
        self.host = host
        self.port = port
        self.timeout = timeout
        self.transport = transport
    }

    public func call(_ command: String, parameter: String? = nil) async throws -> [String: JSONValue] {
        var payloadDict: [String: JSONValue] = ["command": .string(command)]
        if let parameter, !parameter.isEmpty {
            payloadDict["parameter"] = .string(parameter)
        }
        let payload = try JSONEncoder().encode(JSONValue.object(payloadDict))
        let raw = try await send(payload)
        return try Self.parseResponse(Self.decode(raw))
    }

    public func callText(_ command: String) async throws -> [String: JSONValue] {
        let raw = try await send(Data(command.utf8))
        return try Self.parseResponse(Self.decode(raw))
    }

    private func send(_ payload: Data) async throws -> Data {
        try Task.checkCancellation()
        if let transport {
            return try await transport(host, port, timeout, payload)
        }
        let host = self.host
        let port = self.port
        let timeout = self.timeout
        return try await Task.detached(priority: .utility) {
            try Self.sendSync(host: host, port: port, timeout: timeout, payload: payload)
        }.value
    }

    public static func decode(_ raw: Data) -> String {
        guard !raw.isEmpty else { return "" }
        let text = String(data: raw, encoding: .utf8) ?? String(data: raw, encoding: .isoLatin1) ?? ""
        let trimSet = CharacterSet(charactersIn: "\0\r\n ")
        return text.trimmingCharacters(in: trimSet)
    }

    public static func parseResponse(_ text: String) throws -> [String: JSONValue] {
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: "\0\r\n "))
        guard !trimmed.isEmpty else { throw CgminerError.emptyResponse }

        if let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(JSONValue.self, from: data),
           case .object(let dict) = decoded {
            return dict
        }

        let parts = trimmed.split(separator: "|").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        guard !parts.isEmpty else {
            throw CgminerError.unparseableResponse(String(trimmed.prefix(80)))
        }

        var out: [String: JSONValue] = ["_raw_text": .string(trimmed)]
        var parsedAny = false
        for part in parts {
            let sectionDict = parseKVSection(part)
            guard !sectionDict.isEmpty else { continue }
            parsedAny = true
            let sectionName = sectionDict["_section"]?.stringValue ?? "MISC"
            let sectionObj = JSONValue.object(sectionDict)
            if let existing = out[sectionName] {
                if case .array(var list) = existing {
                    list.append(sectionObj)
                    out[sectionName] = .array(list)
                } else {
                    out[sectionName] = .array([existing, sectionObj])
                }
            } else {
                out[sectionName] = sectionObj
            }
        }
        guard parsedAny else {
            throw CgminerError.unparseableResponse(String(trimmed.prefix(80)))
        }
        return out
    }

    private static func parseKVSection(_ part: String) -> [String: JSONValue] {
        var section: [String: JSONValue] = [:]
        var groups: [String: JSONValue] = [:]
        var items = part.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        guard !items.isEmpty else { return section }

        if !items[0].contains("=") {
            section["_section"] = .string(items[0])
            items.removeFirst()
        }

        for item in items {
            guard let eqIndex = item.firstIndex(of: "=") else { continue }
            let key = String(item[..<eqIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(item[item.index(after: eqIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            if value.contains("[") && value.hasSuffix("]") && value.contains(" ") {
                let bracketed = parseBracketed(value)
                if !bracketed.isEmpty {
                    groups[key] = .object(bracketed.mapValues { .string($0) })
                    section[key] = .string(value)
                    continue
                }
            }
            section[key] = coerce(value)
        }
        if !groups.isEmpty {
            section["_groups"] = .object(groups)
        }
        return section
    }

    public static func parseBracketed(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        var token = ""
        var depth = 0
        for ch in text + " " {
            if ch == "[" {
                depth += 1
                token.append(ch)
            } else if ch == "]" {
                depth -= 1
                token.append(ch)
            } else if ch == " " && depth == 0 {
                if !token.isEmpty {
                    if let openIdx = token.firstIndex(of: "["), token.hasSuffix("]") {
                        let name = String(token[..<openIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
                        let valStart = token.index(after: openIdx)
                        let valEnd = token.index(before: token.endIndex)
                        let val = String(token[valStart..<valEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty {
                            out[name] = val
                        }
                    }
                    token = ""
                }
            } else {
                token.append(ch)
            }
        }
        return out
    }

    private static func coerce(_ value: String) -> JSONValue {
        guard !value.isEmpty else { return .string("") }
        if !value.contains("."), let intVal = Int64(value) {
            return .integer(intVal)
        }
        if value.contains("."), let doubleVal = Double(value), doubleVal.isFinite {
            return .number(doubleVal)
        }
        return .string(value)
    }

    #if canImport(Darwin)
    public static func isPortOpen(host: String, port: Int, timeout: TimeInterval) -> Bool {
        guard let fd = try? connectSocket(host: host, port: port, timeout: timeout) else {
            return false
        }
        Darwin.close(fd)
        return true
    }

    private static func connectSocket(host: String, port: Int, timeout: TimeInterval) throws -> Int32 {
        let cleanHost = host.hasPrefix("[") && host.hasSuffix("]")
            ? String(host.dropFirst().dropLast())
            : host
        guard !cleanHost.isEmpty, (1...65_535).contains(port) else {
            throw CgminerError.invalidHost(host)
        }
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP
        var res: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(cleanHost, String(port), &hints, &res)
        guard status == 0, let first = res else {
            throw CgminerError.connectionFailed("Address resolution failed for \(host):\(port)")
        }
        defer { freeaddrinfo(first) }

        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let info = cursor {
            defer { cursor = info.pointee.ai_next }
            let fd = Darwin.socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
            guard fd >= 0 else { continue }

            var noSigPipe: Int32 = 1
            _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

            let flags = fcntl(fd, F_GETFL, 0)
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

            let connectRes = Darwin.connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen)
            if connectRes == 0 {
                _ = fcntl(fd, F_SETFL, flags)
                return fd
            }
            if errno == EINPROGRESS {
                var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                let timeoutMs = Int32(max(50, min(timeout * 1_000, 30_000)))
                let pollRes = Darwin.poll(&pfd, 1, timeoutMs)
                if pollRes > 0 && (pfd.revents & Int16(POLLOUT)) != 0 {
                    var soError: Int32 = 0
                    var len = socklen_t(MemoryLayout<Int32>.size)
                    if getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len) == 0 && soError == 0 {
                        _ = fcntl(fd, F_SETFL, flags)
                        return fd
                    }
                }
            }
            Darwin.close(fd)
        }
        throw CgminerError.connectionFailed("Connection refused or unreachable at \(host):\(port)")
    }

    private static func sendSync(host: String, port: Int, timeout: TimeInterval, payload: Data) throws -> Data {
        let fd = try connectSocket(host: host, port: port, timeout: timeout)
        defer { Darwin.close(fd) }

        let secs = max(1, Int(ceil(timeout)))
        var tv = timeval(tv_sec: secs, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        try payload.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var sent = 0
            while sent < rawBuffer.count {
                let n = Darwin.send(fd, base.advanced(by: sent), rawBuffer.count - sent, 0)
                if n <= 0 {
                    throw CgminerError.connectionFailed("Write failed to \(host):\(port)")
                }
                sent += n
            }
        }

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while response.count < 262_144 {
            let n = Darwin.recv(fd, &buffer, buffer.count, 0)
            if n > 0 {
                response.append(buffer, count: n)
            } else if n == 0 {
                break
            } else {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    if !response.isEmpty { break }
                    throw CgminerError.timeout(host)
                }
                throw CgminerError.connectionFailed("Read failed from \(host):\(port)")
            }
        }
        return response
    }
    #else
    public static func isPortOpen(host: String, port: Int, timeout: TimeInterval) -> Bool { false }
    private static func sendSync(host: String, port: Int, timeout: TimeInterval, payload: Data) throws -> Data {
        throw CgminerError.connectionFailed("Socket transport unavailable on this platform")
    }
    #endif
}
