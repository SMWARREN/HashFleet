import Foundation
import Security

struct FleetRemotePushIdentity: Codable, Sendable {
    let id: String
    let secret: String
    var isValid: Bool {
        guard UUID(uuidString: id)?.uuidString.lowercased() == id, secret.utf8.count == 43,
              secret.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0)
                  || (97...122).contains($0) || $0 == 45 || $0 == 95 }),
              let raw = Data(base64Encoded: secret.replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/") + "="), raw.count == 32 else { return false }
        return raw.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") == secret
    }
}

@MainActor
protocol FleetRemotePushCredentialStore {
    func load() throws -> FleetRemotePushIdentity?
    func save(_ identity: FleetRemotePushIdentity) throws
    func clear() throws
}

@MainActor
struct FleetRemotePushKeychain: FleetRemotePushCredentialStore {
    private let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "app.hashfleet.remote-push",
        kSecAttrAccount as String: "installation"
    ]
    func load() throws -> FleetRemotePushIdentity? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw FleetRemotePushError.credentials }
        let identity = try JSONDecoder().decode(FleetRemotePushIdentity.self, from: data)
        guard identity.isValid else { throw FleetRemotePushError.credentials }
        return identity
    }
    func save(_ identity: FleetRemotePushIdentity) throws {
        let data = try JSONEncoder().encode(identity)
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw FleetRemotePushError.credentials }
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw FleetRemotePushError.credentials }
    }
    static func generate() throws -> FleetRemotePushIdentity {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw FleetRemotePushError.credentials
        }
        let secret = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return FleetRemotePushIdentity(id: UUID().uuidString.lowercased(), secret: secret)
    }
}

enum FleetRemotePushError: Error {
    case credentials, connection, permission, invalidResponse, authentication, rateLimited, restricted
    var message: String {
        switch self {
        case .credentials: "Could not access secure notification credentials. Please try again after unlocking your device."
        case .permission: "Allow notifications in \(FleetDeviceCopy.hostSettingsAppName) before enabling scheduled summaries."
        case .authentication: "The notification service could not verify this connection. Reconnect before enabling summaries."
        case .rateLimited: "The notification service is receiving too many requests. Please wait before retrying."
        case .restricted: "Cloud enrollment and scheduled LAN checks are disabled in demos and automated tests."
        case .connection, .invalidResponse: "Could not sync with hashfleet.app. The last saved server schedule may still apply."
        }
    }
}

protocol FleetRemotePushTransport: Sendable {
    func send(action: String, method: String, identity: FleetRemotePushIdentity,
              body: Data?) async throws -> FleetRemotePushReply
}

final class FleetRemotePushRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // A redirect must never forward an installation credential to a different endpoint.
        completionHandler(nil)
    }
}

struct FleetRemotePushClient: FleetRemotePushTransport {
    static let website = URL(string: "https://hashfleet.app")!
    let session: URLSession
    let endpoint: URL

    init(session: URLSession? = nil, endpoint: URL = website.appendingPathComponent("api/v1.php")) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        self.session = session ?? URLSession(configuration: configuration, delegate: FleetRemotePushRedirectGuard(),
                                            delegateQueue: nil)
        self.endpoint = endpoint
    }

    func send(action: String, method: String, identity: FleetRemotePushIdentity,
              body: Data?) async throws -> FleetRemotePushReply {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.host == "hashfleet.app",
              components.port == nil || components.port == 443,
              components.path == "/api/v1.php", components.user == nil, components.password == nil,
              components.fragment == nil, components.query == nil,
              ["register": ["POST", "DELETE"], "preferences": ["GET", "PUT"], "status": ["GET"]][action]?.contains(method) == true,
              identity.isValid,
              body.map({ $0.count <= 131_072 }) ?? true else { throw FleetRemotePushError.connection }
        components.queryItems = [URLQueryItem(name: "action", value: action)]
        guard let url = components.url else { throw FleetRemotePushError.connection }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(identity.secret)", forHTTPHeaderField: "Authorization")
        request.setValue(identity.id, forHTTPHeaderField: "X-HashFleet-Installation")
        do {
            try Task.checkCancellation()
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse else { throw FleetRemotePushError.invalidResponse }
            if http.statusCode == 401 || http.statusCode == 403 { throw FleetRemotePushError.authentication }
            if http.statusCode == 429 { throw FleetRemotePushError.rateLimited }
            guard (200..<300).contains(http.statusCode), http.expectedContentLength <= 131_072,
                  http.url?.host == endpoint.host, http.url?.path == endpoint.path else {
                throw FleetRemotePushError.invalidResponse
            }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 131_072 else { throw FleetRemotePushError.invalidResponse }
                try Task.checkCancellation()
                data.append(byte)
            }
            let reply = try JSONDecoder().decode(FleetRemotePushReply.self, from: data)
            guard reply.ok, method == "DELETE" || (reply.mode == "device_check_v1" && reply.settings != nil && reply.providerReady != nil),
                  reply.settings.map({ $0.miners.count <= 64 && Set($0.miners.map(\.id)).count == $0.miners.count }) ?? true else {
                throw FleetRemotePushError.invalidResponse
            }
            return reply
        } catch let error as FleetRemotePushError { throw error } catch { throw FleetRemotePushError.connection }
    }
}
