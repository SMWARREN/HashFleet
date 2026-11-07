import Foundation
import Observation
import HashFleetCore

private struct FirmwareGitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL?
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
    }
}

/// A release from the miner's own open-source firmware project. The link is informational only.
struct FirmwareRelease: Codable, Equatable, Identifiable, Sendable {
    let version: String
    let url: URL?

    var id: String { version }
}

/// A read-only release comparison for one miner. The release check never flashes or changes firmware.
struct FirmwareUpdateNotice: Codable, Equatable, Sendable {
    let currentVersion: String
    let releases: [FirmwareRelease]
    let checkedAt: Date
    let checkFailed: Bool

    var latestRelease: FirmwareRelease? {
        releases.reduce(nil) { best, release in
            guard let releaseVersion = FirmwareVersion(release.version) else { return best ?? release }
            guard let best, let bestVersion = FirmwareVersion(best.version) else { return release }
            return releaseVersion > bestVersion ? release : best
        }
    }

    var latestVersion: String? { latestRelease?.version }

    var isUpdateAvailable: Bool {
        guard let latestVersion,
            let current = FirmwareVersion(currentVersion),
            let latest = FirmwareVersion(latestVersion)
        else { return false }
        return latest > current
    }

    var isComparable: Bool {
        guard let latestVersion else { return false }
        return FirmwareVersion(currentVersion) != nil && FirmwareVersion(latestVersion) != nil
    }
}

/// Checks the official ESP-Miner release feed at most once per miner per day.
///
/// This is deliberately separate from foreground telemetry. Opening a miner may use a cached
/// result immediately, but it never causes a firmware write and a failed public-feed check is shown
/// as unavailable rather than as an update or an out-of-date claim.
@MainActor @Observable
final class FirmwareUpdateStore {
    static let checkInterval: TimeInterval = 24 * 60 * 60
    /// Retained for the Bitaxe family. Prefer `MinerFirmwareFamily.releaseFeedURL`, which keeps a
    /// NerdQAxe owner from being offered a Bitaxe build.
    static let releaseFeedURL = MinerFirmwareFamily.bitaxe.releaseFeedURL

    private(set) var notices: [UUID: FirmwareUpdateNotice] = [:]
    /// The release version dismissed for each miner. A newer release automatically becomes visible.
    private(set) var dismissedReleaseByDevice: [UUID: String] = [:]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var checksInFlight: Set<UUID> = []
    private static let storageKey = "app.hashfleet.firmware-update-notices.v1"
    private static let dismissedStorageKey = "app.hashfleet.firmware-update-dismissed.v1"

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
        if let data = defaults.data(forKey: Self.storageKey),
            let decoded = try? JSONDecoder().decode([UUID: FirmwareUpdateNotice].self, from: data) {
            notices = decoded
        }
        if let data = defaults.data(forKey: Self.dismissedStorageKey),
            let decoded = try? JSONDecoder().decode([UUID: String].self, from: data) {
            dismissedReleaseByDevice = decoded
        }
    }

    func notice(for deviceID: UUID) -> FirmwareUpdateNotice? {
        notices[deviceID]
    }

    func shouldShow(_ notice: FirmwareUpdateNotice, for deviceID: UUID) -> Bool {
        guard notice.isUpdateAvailable, let latestVersion = notice.latestVersion else { return false }
        return dismissedReleaseByDevice[deviceID] != latestVersion
    }

    /// Hides this release for one miner. The notice is eligible again as soon as a newer release is
    /// returned by GitHub, without requiring a manual reset or showing an already-dismissed banner.
    func dismiss(deviceID: UUID, releaseVersion: String) {
        dismissedReleaseByDevice[deviceID] = releaseVersion
        persistDismissals()
    }

    /// Uses the saved release result while it is fresh. A changed installed version is compared
    /// against the saved latest release without spending another network request.
    func checkIfNeeded(device: MinerDevice, info: MinerInfo?) async {
        guard let currentVersion = Self.currentVersion(from: info) else { return }
        // Without evidence of which project this miner runs, offering any release feed risks
        // pointing the owner at the wrong firmware. Stay silent instead of guessing.
        guard let family = MinerFirmwareFamily.identify(from: info) else { return }

        let now = Date()
        if let cached = notices[device.id],
            cached.checkedAt <= now,
            now.timeIntervalSince(cached.checkedAt) < Self.checkInterval {
            if cached.currentVersion != currentVersion {
                notices[device.id] = FirmwareUpdateNotice(
                    currentVersion: currentVersion,
                    releases: cached.releases,
                    checkedAt: cached.checkedAt,
                    checkFailed: cached.checkFailed
                )
                persist()
            }
            return
        }

        guard !checksInFlight.contains(device.id) else { return }
        checksInFlight.insert(device.id)
        defer { checksInFlight.remove(device.id) }

        do {
            let releases = try await Self.fetchReleases(session: session, family: family)
            try Task.checkCancellation()
            notices[device.id] = FirmwareUpdateNotice(
                currentVersion: currentVersion,
                releases: releases,
                checkedAt: Date(),
                checkFailed: false
            )
        } catch is CancellationError {
            return
        } catch {
            // URLSession reports a cancelled request as URLError.cancelled, not necessarily
            // CancellationError. Leaving the screen must not cache an offline failure.
            guard !Task.isCancelled, (error as? URLError)?.code != .cancelled else { return }
            // Do not echo a remote error, URL, or device address into the UI. A failed check is
            // still timestamped so opening a detail screen cannot hammer GitHub while offline.
            notices[device.id] = FirmwareUpdateNotice(
                currentVersion: currentVersion,
                releases: [],
                checkedAt: Date(),
                checkFailed: true
            )
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(notices) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func persistDismissals() {
        guard let data = try? JSONEncoder().encode(dismissedReleaseByDevice) else { return }
        defaults.set(data, forKey: Self.dismissedStorageKey)
    }

    private static func fetchReleases(
        session: URLSession,
        family: MinerFirmwareFamily
    ) async throws -> [FirmwareRelease] {
        var request = URLRequest(
            url: family.releaseFeedURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10
        )
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("HashFleet firmware update checker", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw FirmwareUpdateError.invalidResponse
        }
        let payload = try JSONDecoder().decode([FirmwareGitHubRelease].self, from: data)
        var seen = Set<String>()
        let releases = payload.compactMap { release -> FirmwareRelease? in
            guard !release.draft, !release.prerelease else { return nil }
            let version = release.tagName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !version.isEmpty, seen.insert(version).inserted else { return nil }
            return FirmwareRelease(version: version, url: release.htmlURL)
        }
        guard !releases.isEmpty else { throw FirmwareUpdateError.invalidResponse }
        return releases.sorted { lhs, rhs in
            guard let left = FirmwareVersion(lhs.version), let right = FirmwareVersion(rhs.version) else {
                return lhs.version.localizedStandardCompare(rhs.version) == .orderedDescending
            }
            return left > right
        }
    }

    static func currentVersion(from info: MinerInfo?) -> String? {
        guard let info else { return nil }
        for key in ["version", "firmwareVersion", "axeOSVersion"] {
            guard let value = info.raw[key] else { continue }
            let text: String?
            switch value {
            case .string(let raw): text = raw
            case .number, .integer, .unsignedInteger: text = value.stringValue
            default: text = nil
            }
            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private enum FirmwareUpdateError: Error {
        case invalidResponse
    }
}

/// Small semantic-version parser. Firmware tags commonly include a leading `v`, while installed
/// telemetry may include a prefix or suffix. Only numeric components participate in comparison.
private struct FirmwareVersion: Comparable {
    let components: [Int]

    init?(_ raw: String) {
        let values = raw.split { !$0.isNumber }.prefix(3).compactMap { Int($0) }
        guard !values.isEmpty else { return nil }
        components = Array(values) + Array(repeating: 0, count: max(0, 3 - values.count))
    }

    static func < (lhs: FirmwareVersion, rhs: FirmwareVersion) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

/// Drops drafts and prereleases; duplicates of one tag collapse to first sighting.
