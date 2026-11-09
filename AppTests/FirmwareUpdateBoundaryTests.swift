// One cohesive suite: the transport fixture and 40+ cases share private helpers, and the file
// is intentionally kept as a single unit rather than split across files.
// swiftlint:disable file_length
import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

// MARK: - Isolated transport

/// Per-test transport state, keyed by an `X-Test-ID` header that each test injects through its own
/// ephemeral `URLSession`. Parallel tests therefore never observe each other's requests, and no
/// request ever leaves the process.
final class FirmwareFeedRegistry: @unchecked Sendable {
    enum Action: Sendable {
        /// Answers immediately with an HTTP response.
        case http(status: Int, body: Data)
        /// Answers with a response that is not an `HTTPURLResponse`.
        case nonHTTP(Data)
        /// Fails at the transport layer.
        case fail(URLError)
        /// Keeps the request open until `releaseHeld` is called (or the request is cancelled).
        case hold(Data)
    }

    private struct Entry {
        var queue: [Action] = []
        var history: [URLRequest] = []
        var held: [(proto: FirmwareFeedProtocol, body: Data)] = []
        var cancelledWhileHeld = 0
    }

    static let shared = FirmwareFeedRegistry()

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func enqueue(_ actions: [Action], for id: String) {
        lock.withLock { entries[id, default: Entry()].queue.append(contentsOf: actions) }
    }

    func history(for id: String) -> [URLRequest] {
        lock.withLock { entries[id]?.history ?? [] }
    }

    func cancelledWhileHeld(for id: String) -> Int {
        lock.withLock { entries[id]?.cancelledWhileHeld ?? 0 }
    }

    func clear(_ id: String) {
        lock.withLock { _ = entries.removeValue(forKey: id) }
    }

    /// Records the request and returns the next scripted action. An exhausted script yields nil,
    /// which the protocol turns into an error so an unexpected extra request is visible both as a
    /// history entry and as a failed check.
    func next(for id: String, request: URLRequest, proto: FirmwareFeedProtocol) -> Action? {
        lock.withLock {
            entries[id, default: Entry()].history.append(request)
            guard var entry = entries[id], !entry.queue.isEmpty else { return nil }
            let action = entry.queue.removeFirst()
            if case .hold(let body) = action {
                entry.held.append((proto, body))
            }
            entries[id] = entry
            return action
        }
    }

    /// Called from `stopLoading`. Counts a still-held request that was torn down by the caller,
    /// which is what task cancellation looks like to a `URLProtocol`.
    func noteStopped(_ proto: FirmwareFeedProtocol, for id: String) {
        lock.withLock {
            guard var entry = entries[id],
                let index = entry.held.firstIndex(where: { $0.proto === proto })
            else { return }
            entry.held.remove(at: index)
            entry.cancelledWhileHeld += 1
            entries[id] = entry
        }
    }

    func releaseHeld(for id: String) {
        let held: [(proto: FirmwareFeedProtocol, body: Data)] = lock.withLock {
            guard var entry = entries[id] else { return [] }
            let current = entry.held
            entry.held = []
            entries[id] = entry
            return current
        }
        for item in held { item.proto.deliver(status: 200, body: item.body) }
    }
}

final class FirmwareFeedProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private var testID: String { request.value(forHTTPHeaderField: "X-Test-ID") ?? "unknown" }

    override func startLoading() {
        let action = FirmwareFeedRegistry.shared.next(for: testID, request: request, proto: self)
        switch action {
        case .http(let status, let body):
            deliver(status: status, body: body)
        case .nonHTTP(let body):
            let response = URLResponse(
                url: request.url!, mimeType: "application/json",
                expectedContentLength: body.count, textEncodingName: nil)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .fail(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .hold:
            break
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
        }
    }

    override func stopLoading() {
        FirmwareFeedRegistry.shared.noteStopped(self, for: testID)
    }

    func deliver(status: Int, body: Data) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

// MARK: - Fixtures

private let noticesKey = "app.hashfleet.firmware-update-notices.v1"
private let dismissedKey = "app.hashfleet.firmware-update-dismissed.v1"

private func fwRelease(
    _ tag: String,
    draft: Bool = false,
    prerelease: Bool = false,
    url: String? = nil
) -> [String: Any] {
    [
        "tag_name": tag,
        "html_url": url.map { $0 as Any } ?? NSNull(),
        "draft": draft,
        "prerelease": prerelease
    ]
}

private func feed(_ releases: [[String: Any]]) -> Data {
    // swiftlint:disable:next force_try
    try! JSONSerialization.data(withJSONObject: releases)
}

private func releaseURL(_ tag: String) -> String {
    "https://github.com/bitaxeorg/ESP-Miner/releases/tag/\(tag)"
}

private func simpleFeed(_ tags: [String]) -> Data {
    feed(tags.map { fwRelease($0, url: releaseURL($0)) })
}

private let fwValidBody = simpleFeed(["v2.0.0"])

private func miner(version: String = "v1.0.0", board: String = "Bitaxe Gamma 601") -> MinerInfo {
    MinerInfo(raw: ["version": .string(version), "boardVersion": .string(board)])
}

/// One suite instance exists per test (and per parameterized argument), so every test owns a fresh
/// UserDefaults domain, a fresh ephemeral session and a fresh transport script.
@MainActor
@Suite("Firmware release checker boundaries", .timeLimit(.minutes(1)))
// swiftlint:disable:next type_body_length
final class FirmwareUpdateBoundaryTests {
    private let id: String
    private let suite: String
    private let defaults: UserDefaults
    private let session: URLSession

    init() {
        let testID = UUID().uuidString
        id = testID
        let suiteName = "app.hashfleet.tests.firmware.\(testID)"
        suite = suiteName
        defaults = UserDefaults(suiteName: suiteName)!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FirmwareFeedProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Test-ID": testID]
        session = URLSession(configuration: configuration)
    }

    isolated deinit {
        session.invalidateAndCancel()
        defaults.removePersistentDomain(forName: suite)
        FirmwareFeedRegistry.shared.clear(id)
    }

    // MARK: helpers

    private func makeStore() -> FirmwareUpdateStore {
        FirmwareUpdateStore(defaults: defaults, session: session)
    }

    private func device(_ name: String = "Gamma") -> MinerDevice {
        MinerDevice(name: name, address: "\(name.lowercased())-\(id).local")
    }

    private func script(_ actions: FirmwareFeedRegistry.Action...) {
        FirmwareFeedRegistry.shared.enqueue(actions, for: id)
    }

    private var requests: [URLRequest] { FirmwareFeedRegistry.shared.history(for: id) }

    private func seed(_ notices: [UUID: FirmwareUpdateNotice]) throws {
        defaults.set(try JSONEncoder().encode(notices), forKey: noticesKey)
    }

    private func persistedNotices() throws -> [UUID: FirmwareUpdateNotice]? {
        guard let data = defaults.data(forKey: noticesKey) else { return nil }
        return try JSONDecoder().decode([UUID: FirmwareUpdateNotice].self, from: data)
    }

    private func waitUntil(
        _ what: String,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for \(what)", sourceLocation: sourceLocation)
        throw URLError(.timedOut)
    }

    // MARK: request shape

    @Test("Feed request is a read-only, credential-free GET to the Bitaxe release feed")
    func requestIsReadOnlyGET() async throws {
        let store = makeStore()
        let miner1 = device()
        script(.http(status: 200, body: simpleFeed(["v1.2.0"])))
        let before = Date()

        await store.checkIfNeeded(device: miner1, info: miner())

        let sent = try #require(requests.first)
        #expect(requests.count == 1)
        #expect(sent.url == MinerFirmwareFamily.bitaxe.releaseFeedURL)
        #expect(sent.url == FirmwareUpdateStore.releaseFeedURL)
        #expect(sent.httpMethod == "GET")
        #expect(sent.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(sent.value(forHTTPHeaderField: "User-Agent") == "HashFleet firmware update checker")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(sent.httpBody == nil)
        #expect(sent.httpBodyStream == nil)
        #expect(sent.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(sent.timeoutInterval == 10)
        // A release check never talks to the miner itself, so it cannot write to hardware.
        #expect(requests.allSatisfy { $0.url?.host == "api.github.com" })
        #expect(requests.allSatisfy { $0.httpMethod == "GET" })
        #expect(requests.allSatisfy { $0.url?.host?.contains(miner1.address) != true })

        let notice = try #require(store.notice(for: miner1.id))
        #expect(notice.currentVersion == "v1.0.0")
        #expect(notice.releases.map(\.version) == ["v1.2.0"])
        #expect(notice.releases.first?.url?.absoluteString == releaseURL("v1.2.0"))
        #expect(!notice.checkFailed)
        #expect(notice.checkedAt >= before.addingTimeInterval(-1))
        #expect(notice.checkedAt <= Date().addingTimeInterval(1))
        #expect(notice.isUpdateAvailable)
        #expect(notice.isComparable)
        #expect(store.shouldShow(notice, for: miner1.id))
    }

    @Test("Each firmware family requests only its own project feed", arguments: MinerFirmwareFamily.allCases)
    func familyFeedIsUsed(family: MinerFirmwareFamily) async throws {
        let store = makeStore()
        let target = device()
        let board = family == .bitaxe ? "Bitaxe Supra" : "NerdQAxe++"
        script(.http(status: 200, body: simpleFeed(["v3.0.0"])))

        await store.checkIfNeeded(device: target, info: miner(version: "v2.0.0", board: board))

        #expect(requests.map(\.url) == [family.releaseFeedURL])
        #expect(store.notice(for: target.id)?.latestVersion == "v3.0.0")
        let others = MinerFirmwareFamily.allCases.filter { $0 != family }
        #expect(others.allSatisfy { $0.releaseFeedURL != family.releaseFeedURL })
    }

    // MARK: eligibility

    struct SilentCase: Sendable, CustomTestStringConvertible {
        let name: String
        let info: MinerInfo?
        var testDescription: String { name }
    }

    @Test("No version or no family evidence means no request and no notice", arguments: [
        SilentCase(name: "no telemetry", info: nil),
        SilentCase(name: "family but no version", info: MinerInfo(raw: ["boardVersion": .string("Bitaxe Gamma")])),
        SilentCase(
            name: "family but blank version",
            info: MinerInfo(raw: ["version": .string("   \n"), "boardVersion": .string("Bitaxe Gamma")])),
        SilentCase(
            name: "version but unknown family",
            info: MinerInfo(raw: ["version": .string("v1.0.0"), "boardVersion": .string("Mystery Board")])),
        SilentCase(
            name: "version but empty evidence",
            info: MinerInfo(raw: ["version": .string("v1.0.0")]))
    ])
    func silentWithoutEvidence(testCase: SilentCase) async {
        let store = makeStore()
        let target = device()
        script(.http(status: 200, body: simpleFeed(["v9.0.0"])))

        await store.checkIfNeeded(device: target, info: testCase.info)

        #expect(requests.isEmpty)
        #expect(store.notice(for: target.id) == nil)
        #expect(store.notices.isEmpty)
        #expect(defaults.data(forKey: noticesKey) == nil)
    }

    struct VersionCase: Sendable, CustomTestStringConvertible {
        let name: String
        let raw: [String: JSONValue]
        let expected: String?
        var testDescription: String { name }
    }

    @Test("Installed version is read from the first usable telemetry key", arguments: [
        VersionCase(name: "trims whitespace", raw: ["version": .string(" v1.2.3\n")], expected: "v1.2.3"),
        VersionCase(name: "firmwareVersion fallback", raw: ["firmwareVersion": .string("2.0.1")], expected: "2.0.1"),
        VersionCase(name: "axeOSVersion fallback", raw: ["axeOSVersion": .string("v2.5.0")], expected: "v2.5.0"),
        VersionCase(
            name: "version wins over later keys",
            raw: ["version": .string("1.0.0"), "firmwareVersion": .string("2.0.0")], expected: "1.0.0"),
        VersionCase(
            name: "blank version falls through",
            raw: ["version": .string("  "), "firmwareVersion": .string("3.1.0")], expected: "3.1.0"),
        VersionCase(
            name: "bool version falls through",
            raw: ["version": .bool(true), "firmwareVersion": .string("1.0.0")], expected: "1.0.0"),
        VersionCase(name: "integer version", raw: ["version": .integer(7)], expected: "7"),
        VersionCase(name: "fractional version", raw: ["version": .number(2.5)], expected: "2.5"),
        VersionCase(
            name: "huge unsigned version",
            raw: ["version": .unsignedInteger(UInt64.max)], expected: "18446744073709551615"),
        VersionCase(name: "null version", raw: ["version": .null], expected: nil),
        VersionCase(name: "object version", raw: ["version": .object([:])], expected: nil),
        VersionCase(name: "array version", raw: ["version": .array([.string("1.0.0")])], expected: nil),
        VersionCase(name: "empty telemetry", raw: [:], expected: nil)
    ])
    func currentVersionExtraction(testCase: VersionCase) {
        #expect(FirmwareUpdateStore.currentVersion(from: MinerInfo(raw: testCase.raw)) == testCase.expected)
        #expect(FirmwareUpdateStore.currentVersion(from: nil) == nil)
    }

    // MARK: feed parsing

    @Test("Drafts, prereleases, blank tags and duplicate tags never become releases")
    func feedFiltering() async throws {
        let store = makeStore()
        let target = device()
        let payload = feed([
            fwRelease("v1.0.0", url: releaseURL("first")),
            fwRelease("v9.9.9", draft: true, url: releaseURL("v9.9.9")),
            fwRelease("v8.8.8", prerelease: true, url: releaseURL("v8.8.8")),
            fwRelease("v7.7.7", draft: true, prerelease: true),
            fwRelease("   "),
            fwRelease(""),
            fwRelease(" v1.0.0 ", url: releaseURL("second")),
            fwRelease("v1.1.0\n"),
            fwRelease("v1.0.0", url: releaseURL("third"))
        ])
        script(.http(status: 200, body: payload))

        await store.checkIfNeeded(device: target, info: miner(version: "v0.9.0"))

        let notice = try #require(store.notice(for: target.id))
        #expect(!notice.checkFailed)
        #expect(notice.releases.map(\.version) == ["v1.1.0", "v1.0.0"])
        // The first sighting of a duplicated tag wins, and a missing URL stays nil.
        #expect(notice.releases.last?.url?.absoluteString == releaseURL("first"))
        #expect(notice.releases.first?.url == nil)
        #expect(notice.releases.map(\.id) == ["v1.1.0", "v1.0.0"])
        #expect(notice.latestVersion == "v1.1.0")
        #expect(!notice.releases.contains { ["v9.9.9", "v8.8.8", "v7.7.7"].contains($0.version) })
    }

    @Test("Releases sort by numeric version, not lexically")
    func semanticSort() async throws {
        let store = makeStore()
        let target = device()
        script(.http(status: 200, body: simpleFeed(["v2.9.0", "v10.0.0", "v2.10.0", "v2.2.1", "v1.9.9", "v2.10.1"])))

        await store.checkIfNeeded(device: target, info: miner(version: "v2.10.0"))

        let notice = try #require(store.notice(for: target.id))
        #expect(notice.releases.map(\.version) == ["v10.0.0", "v2.10.1", "v2.10.0", "v2.9.0", "v2.2.1", "v1.9.9"])
        #expect(notice.latestVersion == "v10.0.0")
        #expect(notice.isUpdateAvailable)
        #expect(notice.isComparable)
    }

    @Test("A feed with no numeric tags falls back to natural descending order and is not comparable")
    func nonNumericTagsFallBack() async throws {
        let store = makeStore()
        let target = device()
        script(.http(status: 200, body: simpleFeed(["alpha", "gamma", "beta"])))

        await store.checkIfNeeded(device: target, info: miner())

        let notice = try #require(store.notice(for: target.id))
        #expect(!notice.checkFailed)
        #expect(notice.releases.map(\.version) == ["gamma", "beta", "alpha"])
        #expect(!notice.isComparable)
        #expect(!notice.isUpdateAvailable)
        #expect(!store.shouldShow(notice, for: target.id))
    }

    // MARK: failures

    struct FailureCase: Sendable, CustomTestStringConvertible {
        let name: String
        let action: FirmwareFeedRegistry.Action
        var testDescription: String { name }
    }

    @Test("Every bad response becomes a timestamped, non-claiming failed check", arguments: [
        FailureCase(name: "garbage body", action: .http(status: 200, body: Data("not json".utf8))),
        FailureCase(name: "truncated JSON", action: .http(status: 200, body: Data("[{\"tag_name\":\"v1".utf8))),
        FailureCase(name: "object instead of array", action: .http(status: 200, body: Data("{\"message\":\"Not Found\"}".utf8))),
        FailureCase(name: "empty body", action: .http(status: 200, body: Data())),
        FailureCase(name: "empty array", action: .http(status: 200, body: Data("[]".utf8))),
        FailureCase(
            name: "only drafts and prereleases",
            action: .http(status: 200, body: feed([fwRelease("v3.0.0", draft: true), fwRelease("v4.0.0", prerelease: true)]))),
        FailureCase(
            name: "only blank tags",
            action: .http(status: 200, body: feed([fwRelease(""), fwRelease("  \n")]))),
        FailureCase(name: "HTTP 500 with valid body", action: .http(status: 500, body: fwValidBody)),
        FailureCase(name: "HTTP 403 rate limit with valid body", action: .http(status: 403, body: fwValidBody)),
        FailureCase(name: "HTTP 404", action: .http(status: 404, body: Data("[]".utf8))),
        FailureCase(name: "non-HTTP response", action: .nonHTTP(fwValidBody)),
        FailureCase(name: "offline", action: .fail(URLError(.notConnectedToInternet))),
        FailureCase(name: "timeout", action: .fail(URLError(.timedOut)))
    ])
    func failedChecks(testCase: FailureCase) async throws {
        let store = makeStore()
        let target = device()
        FirmwareFeedRegistry.shared.enqueue([testCase.action], for: id)
        let before = Date()

        await store.checkIfNeeded(device: target, info: miner(version: "v1.0.0"))

        let notice = try #require(store.notice(for: target.id))
        #expect(notice.checkFailed)
        #expect(notice.releases.isEmpty)
        #expect(notice.currentVersion == "v1.0.0")
        #expect(notice.latestRelease == nil)
        #expect(notice.latestVersion == nil)
        #expect(!notice.isUpdateAvailable)
        #expect(!notice.isComparable)
        #expect(!store.shouldShow(notice, for: target.id))
        #expect(notice.checkedAt >= before.addingTimeInterval(-1))

        let persisted = try #require(try persistedNotices())
        #expect(persisted[target.id] == notice)

        // The failure is throttled, so an offline detail screen cannot hammer GitHub.
        await store.checkIfNeeded(device: target, info: miner(version: "v1.0.0"))
        #expect(requests.count == 1)
    }

    @Test("Only 2xx statuses are accepted", arguments: [
        (200, true), (201, true), (299, true), (300, false), (401, false)
    ])
    func statusBoundaries(status: Int, accepted: Bool) async throws {
        let store = makeStore()
        let target = device()
        script(.http(status: status, body: fwValidBody))

        await store.checkIfNeeded(device: target, info: miner())

        let notice = try #require(store.notice(for: target.id))
        #expect(notice.checkFailed == !accepted)
        #expect(notice.releases.map(\.version) == (accepted ? ["v2.0.0"] : []))
    }

    // MARK: throttle and cache

    @Test("A successful check is reused for the whole interval")
    func successfulCheckIsThrottled() async throws {
        let store = makeStore()
        let target = device()
        script(.http(status: 200, body: simpleFeed(["v1.5.0"])), .http(status: 200, body: simpleFeed(["v9.0.0"])))

        await store.checkIfNeeded(device: target, info: miner())
        let first = try #require(store.notice(for: target.id))
        for _ in 0..<3 { await store.checkIfNeeded(device: target, info: miner()) }

        #expect(requests.count == 1)
        #expect(store.notice(for: target.id) == first)
        #expect(first.latestVersion == "v1.5.0")
        #expect(FirmwareUpdateStore.checkInterval == 24 * 60 * 60)
    }

    @Test("A cached notice is refreshed only once it is a full interval old", arguments: [
        (23.0, 0), (25.0, 1), (24.0 * 30, 1)
    ])
    func cacheAgeBoundary(hoursOld: Double, expectedRequests: Int) async throws {
        let target = device()
        let checkedAt = Date().addingTimeInterval(-hoursOld * 3_600)
        try seed([
            target.id: FirmwareUpdateNotice(
                currentVersion: "v1.0.0", releases: [FirmwareRelease(version: "v1.1.0", url: nil)],
                checkedAt: checkedAt, checkFailed: false)
        ])
        let store = makeStore()
        script(.http(status: 200, body: simpleFeed(["v1.4.0"])))

        await store.checkIfNeeded(device: target, info: miner())

        #expect(requests.count == expectedRequests)
        let notice = try #require(store.notice(for: target.id))
        if expectedRequests == 0 {
            #expect(notice.latestVersion == "v1.1.0")
            #expect(notice.checkedAt == checkedAt)
        } else {
            #expect(notice.latestVersion == "v1.4.0")
            #expect(notice.checkedAt > checkedAt)
            #expect(try persistedNotices()?[target.id] == notice)
        }
    }

    @Test("An expired failed check is replaced by a successful one")
    func expiredFailureRecovers() async throws {
        let target = device()
        try seed([
            target.id: FirmwareUpdateNotice(
                currentVersion: "v1.0.0", releases: [], checkedAt: Date().addingTimeInterval(-90_000),
                checkFailed: true)
        ])
        let store = makeStore()
        script(.http(status: 200, body: simpleFeed(["v1.1.0"])))

        await store.checkIfNeeded(device: target, info: miner())

        let notice = try #require(store.notice(for: target.id))
        #expect(!notice.checkFailed)
        #expect(notice.releases.map(\.version) == ["v1.1.0"])
        #expect(requests.count == 1)
    }

    /// A clock set backwards (or a notice written by a device with a fast clock) leaves a cached
    /// `checkedAt` in the future. A negative age should not count as "fresh" for ten days.
    @Test("A cached notice dated in the future does not suppress checks")
    func futureDatedCacheIsTreatedAsStale() async throws {
        let target = device()
        try seed([
            target.id: FirmwareUpdateNotice(
                currentVersion: "v1.0.0", releases: [FirmwareRelease(version: "v1.1.0", url: nil)],
                checkedAt: Date().addingTimeInterval(10 * 24 * 3_600), checkFailed: false)
        ])
        let store = makeStore()
        script(.http(status: 200, body: simpleFeed(["v1.4.0"])))

        await store.checkIfNeeded(device: target, info: miner())

        #expect(requests.count == 1)
        #expect(store.notice(for: target.id)?.latestVersion == "v1.4.0")
    }

    @Test("A changed installed version is compared against the cached release without a request")
    func changedVersionReusesCachedReleases() async throws {
        let store = makeStore()
        let target = device()
        script(.http(status: 200, body: simpleFeed(["v1.2.0", "v1.1.0"])))
        await store.checkIfNeeded(device: target, info: miner(version: "v1.0.0"))
        let first = try #require(store.notice(for: target.id))
        #expect(first.isUpdateAvailable)

        // The owner flashed the update elsewhere, so telemetry now reports the new version.
        await store.checkIfNeeded(device: target, info: miner(version: "v1.2.0"))

        #expect(requests.count == 1)
        let updated = try #require(store.notice(for: target.id))
        #expect(updated.currentVersion == "v1.2.0")
        #expect(updated.releases == first.releases)
        #expect(updated.checkedAt == first.checkedAt)
        #expect(!updated.checkFailed)
        #expect(!updated.isUpdateAvailable)
        #expect(!store.shouldShow(updated, for: target.id))
        #expect(try persistedNotices()?[target.id] == updated)
        #expect(makeStore().notice(for: target.id) == updated)

        // Reporting the same version again changes nothing.
        await store.checkIfNeeded(device: target, info: miner(version: "v1.2.0"))
        #expect(store.notice(for: target.id) == updated)
        #expect(requests.count == 1)
    }

    @Test("A changed version keeps a cached failure marker and still makes no request")
    func changedVersionPreservesFailure() async throws {
        let store = makeStore()
        let target = device()
        script(.http(status: 500, body: Data()))
        await store.checkIfNeeded(device: target, info: miner(version: "v1.0.0"))

        await store.checkIfNeeded(device: target, info: miner(version: "v1.1.0"))

        let notice = try #require(store.notice(for: target.id))
        #expect(notice.currentVersion == "v1.1.0")
        #expect(notice.checkFailed)
        #expect(notice.releases.isEmpty)
        #expect(requests.count == 1)
    }

    // MARK: independence

    @Test("Miners are throttled, cached and fed independently")
    func independentDevices() async throws {
        let store = makeStore()
        let bitaxe = device("Gamma")
        let nerd = device("Nerd")
        script(
            .http(status: 200, body: simpleFeed(["v1.5.0"])),
            .http(status: 200, body: simpleFeed(["v7.0.0"])),
            .http(status: 500, body: Data()))

        await store.checkIfNeeded(device: bitaxe, info: miner(version: "v1.0.0"))
        await store.checkIfNeeded(device: nerd, info: miner(version: "v6.0.0", board: "NerdQAxe++"))
        // A different device is not throttled by the first device's fresh result.
        let third = device("Third")
        await store.checkIfNeeded(device: third, info: miner(version: "v1.0.0"))

        #expect(requests.map(\.url) == [
            MinerFirmwareFamily.bitaxe.releaseFeedURL,
            MinerFirmwareFamily.nerdqaxe.releaseFeedURL,
            MinerFirmwareFamily.bitaxe.releaseFeedURL
        ])
        #expect(store.notice(for: bitaxe.id)?.latestVersion == "v1.5.0")
        #expect(store.notice(for: nerd.id)?.latestVersion == "v7.0.0")
        #expect(store.notice(for: nerd.id)?.currentVersion == "v6.0.0")
        // One miner's failure does not affect the others.
        #expect(store.notice(for: third.id)?.checkFailed == true)
        #expect(store.notice(for: bitaxe.id)?.checkFailed == false)
        #expect(store.notices.count == 3)
        #expect(try persistedNotices()?.count == 3)

        // Dismissing for one miner leaves the others visible.
        let bitaxeNotice = try #require(store.notice(for: bitaxe.id))
        store.dismiss(deviceID: bitaxe.id, releaseVersion: "v1.5.0")
        #expect(!store.shouldShow(bitaxeNotice, for: bitaxe.id))
        #expect(store.shouldShow(bitaxeNotice, for: nerd.id))
    }

    @Test("Concurrent checks for one miner share a single request")
    func concurrentChecksAreDeduplicated() async throws {
        let store = makeStore()
        let target = device()
        script(.hold(simpleFeed(["v1.5.0"])))

        let first = Task { @MainActor in
            await store.checkIfNeeded(device: target, info: miner())
        }
        try await waitUntil("the first request to start") { requests.count == 1 }

        // The second call arrives while the first is in flight and must not start another request.
        await store.checkIfNeeded(device: target, info: miner())
        await store.checkIfNeeded(device: target, info: miner())
        #expect(requests.count == 1)
        #expect(store.notice(for: target.id) == nil)

        FirmwareFeedRegistry.shared.releaseHeld(for: id)
        await first.value

        #expect(requests.count == 1)
        #expect(store.notice(for: target.id)?.latestVersion == "v1.5.0")
        await store.checkIfNeeded(device: target, info: miner())
        #expect(requests.count == 1)
    }

    @Test("Different miners are not deduplicated against each other")
    func concurrentChecksForDifferentDevices() async throws {
        let store = makeStore()
        let one = device("One")
        let two = device("Two")
        script(.hold(simpleFeed(["v1.5.0"])), .hold(simpleFeed(["v1.5.0"])))

        let firstTask = Task { @MainActor in await store.checkIfNeeded(device: one, info: miner()) }
        try await waitUntil("the first request") { requests.count == 1 }
        let secondTask = Task { @MainActor in await store.checkIfNeeded(device: two, info: miner()) }
        try await waitUntil("the second request") { requests.count == 2 }

        FirmwareFeedRegistry.shared.releaseHeld(for: id)
        await firstTask.value
        await secondTask.value

        #expect(requests.count == 2)
        #expect(store.notice(for: one.id)?.latestVersion == "v1.5.0")
        #expect(store.notice(for: two.id)?.latestVersion == "v1.5.0")
    }

    @Test("A cancelled check records nothing and does not throttle the next attempt")
    func cancelledCheckLeavesNoTrace() async throws {
        let store = makeStore()
        let target = device()
        script(.hold(simpleFeed(["v1.5.0"])))

        let task = Task { @MainActor in
            await store.checkIfNeeded(device: target, info: miner())
        }
        try await waitUntil("the request to start") { requests.count == 1 }
        task.cancel()
        await task.value

        // `session.data(for:)` resumes by throwing `URLError.cancelled`, so the producing task can
        // return before URLSession tears down the held request on its own queue and calls
        // `stopLoading`. Wait for that actual cancellation callback instead of racing it; the count
        // must still settle at exactly one, never more.
        try await waitUntil("the held request to observe cancellation") {
            FirmwareFeedRegistry.shared.cancelledWhileHeld(for: id) == 1
        }
        #expect(FirmwareFeedRegistry.shared.cancelledWhileHeld(for: id) == 1)
        // Cancellation (the owner left the screen) is not evidence that GitHub or the network
        // failed, so no failed notice may be stored and the next visit must be free to retry.
        #expect(store.notice(for: target.id) == nil)
        #expect(defaults.data(forKey: noticesKey) == nil)

        script(.http(status: 200, body: simpleFeed(["v1.5.0"])))
        await store.checkIfNeeded(device: target, info: miner())
        #expect(requests.count == 2)
        #expect(store.notice(for: target.id)?.checkFailed == false)
        #expect(store.notice(for: target.id)?.latestVersion == "v1.5.0")
    }

    // MARK: persistence and dismissal

    @Test("Notices and dismissals survive a restart without any request")
    func persistenceAcrossRestart() async throws {
        let store = makeStore()
        let target = device()
        script(.http(status: 200, body: simpleFeed(["v1.5.0"])))
        await store.checkIfNeeded(device: target, info: miner())
        store.dismiss(deviceID: target.id, releaseVersion: "v1.5.0")
        let expected = try #require(store.notice(for: target.id))

        let restored = makeStore()

        #expect(restored.notice(for: target.id) == expected)
        #expect(restored.dismissedReleaseByDevice == [target.id: "v1.5.0"])
        #expect(!restored.shouldShow(expected, for: target.id))
        await restored.checkIfNeeded(device: target, info: miner())
        #expect(requests.count == 1)
    }

    @Test("Corrupt saved data is ignored rather than crashing or inventing notices")
    func corruptPersistedDataIsIgnored() async throws {
        defaults.set(Data("not json".utf8), forKey: noticesKey)
        defaults.set(Data("{\"also\":[1,2".utf8), forKey: dismissedKey)

        let store = makeStore()
        let target = device()

        #expect(store.notices.isEmpty)
        #expect(store.dismissedReleaseByDevice.isEmpty)
        script(.http(status: 200, body: simpleFeed(["v1.5.0"])))
        await store.checkIfNeeded(device: target, info: miner())
        #expect(requests.count == 1)
        #expect(try persistedNotices()?[target.id]?.latestVersion == "v1.5.0")
    }

    @Test("A dismissed release stays hidden until a newer release is fetched")
    func dismissalAcrossFetchedReleases() async throws {
        let target = device()
        let store = makeStore()
        script(.http(status: 200, body: simpleFeed(["v1.2.0", "v1.1.0"])))
        await store.checkIfNeeded(device: target, info: miner(version: "v1.0.0"))
        let current = try #require(store.notice(for: target.id))
        #expect(store.shouldShow(current, for: target.id))

        store.dismiss(deviceID: target.id, releaseVersion: try #require(current.latestVersion))
        #expect(!store.shouldShow(current, for: target.id))
        #expect(requests.count == 1)

        // A day later GitHub publishes v1.3.0. The old dismissal must not hide it.
        try seed([
            target.id: FirmwareUpdateNotice(
                currentVersion: current.currentVersion, releases: current.releases,
                checkedAt: Date().addingTimeInterval(-90_000), checkFailed: false)
        ])
        let restarted = makeStore()
        #expect(!restarted.shouldShow(current, for: target.id))
        script(.http(status: 200, body: simpleFeed(["v1.3.0", "v1.2.0", "v1.1.0"])))
        await restarted.checkIfNeeded(device: target, info: miner(version: "v1.0.0"))

        let newer = try #require(restarted.notice(for: target.id))
        #expect(newer.latestVersion == "v1.3.0")
        #expect(restarted.shouldShow(newer, for: target.id))
        #expect(restarted.dismissedReleaseByDevice[target.id] == "v1.2.0")
    }

    @Test("Notices are only shown when the installed version is older than the latest release")
    func shouldShowRequiresAnAvailableUpdate() async throws {
        let store = makeStore()
        let target = device()
        let release = FirmwareRelease(version: "v1.2.0", url: nil)
        func notice(current: String, failed: Bool = false, releases: [FirmwareRelease]? = nil) -> FirmwareUpdateNotice {
            FirmwareUpdateNotice(
                currentVersion: current, releases: releases ?? [release], checkedAt: Date(), checkFailed: failed)
        }

        #expect(store.shouldShow(notice(current: "v1.1.9"), for: target.id))
        #expect(!store.shouldShow(notice(current: "v1.2.0"), for: target.id))
        #expect(!store.shouldShow(notice(current: "v2.0.0"), for: target.id))
        #expect(!store.shouldShow(notice(current: "garbage"), for: target.id))
        #expect(!store.shouldShow(notice(current: "v1.0.0", releases: []), for: target.id))
        #expect(!store.shouldShow(notice(current: "v1.0.0", failed: true, releases: []), for: target.id))
        #expect(defaults.data(forKey: dismissedKey) == nil)
    }

    // MARK: notice computed properties

    @Test("Notice comparison helpers tolerate prefixes, suffixes, short tags and non-numeric tags")
    func noticeComputedProperties() {
        func notice(_ current: String, _ tags: [String]) -> FirmwareUpdateNotice {
            FirmwareUpdateNotice(
                currentVersion: current,
                releases: tags.map { FirmwareRelease(version: $0, url: nil) },
                checkedAt: Date(), checkFailed: false)
        }

        // Two-component tags pad to three, so v1.2 equals v1.2.0 and is not an update.
        #expect(!notice("1.2.0", ["v1.2"]).isUpdateAvailable)
        #expect(notice("1.1.9", ["v1.2"]).isUpdateAvailable)
        // A telemetry suffix does not change the numeric comparison.
        #expect(!notice("v1.2.0-dirty", ["v1.2.0"]).isUpdateAvailable)
        #expect(notice("v1.2.0-dirty", ["v1.2.1"]).isUpdateAvailable)
        // Non-numeric installed version cannot be compared either way.
        #expect(!notice("unknown", ["v1.2.0"]).isUpdateAvailable)
        #expect(!notice("unknown", ["v1.2.0"]).isComparable)
        #expect(notice("1.0.0", ["v1.2.0"]).isComparable)
        // latestRelease prefers a parseable version over a non-numeric one, in either order,
        // and keeps the first non-numeric tag when nothing parses.
        #expect(notice("1.0.0", ["nightly", "v1.0.0"]).latestVersion == "v1.0.0")
        #expect(notice("1.0.0", ["v1.0.0", "nightly"]).latestVersion == "v1.0.0")
        #expect(notice("1.0.0", ["nightly", "dev"]).latestVersion == "nightly")
        #expect(!notice("1.0.0", ["nightly", "dev"]).isComparable)
        // The highest numeric release wins regardless of input order.
        #expect(notice("1.0.0", ["v1.2.0", "v1.10.0", "v1.9.0"]).latestVersion == "v1.10.0")
        #expect(notice("1.0.0", []).latestRelease == nil)
        #expect(!notice("1.0.0", []).isComparable)
        #expect(!notice("1.0.0", []).isUpdateAvailable)
    }
}
