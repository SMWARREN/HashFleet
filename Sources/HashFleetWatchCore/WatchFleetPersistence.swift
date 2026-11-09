import Foundation

/// Failures a store mutation can report. Messages are safe to show directly.
public enum WatchFleetStoreError: Error, Equatable, Sendable, LocalizedError {
    case duplicateMiner
    case limitReached
    case minerNotFound
    case persistenceFailed
    case demoIsReadOnly

    public var errorDescription: String? {
        switch self {
        case .duplicateMiner: "This miner is already on the Watch."
        case .limitReached: "A Watch can hold up to \(WatchFleetLimits.maximumMiners) miners."
        case .minerNotFound: "That miner is no longer on the Watch."
        case .persistenceFailed: "The Watch couldn't save this change. Nothing was changed."
        case .demoIsReadOnly: "Demo data can't be edited."
        }
    }
}

/// On-disk representation: versioned, validated on load. Contains only configuration and the last successful
/// readings. Raw responses, pool details and Wi-Fi details are never part of it.
struct WatchFleetSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int = WatchFleetSnapshot.currentVersion
    var miners: [WatchMiner]
    var readings: [WatchMinerReading]

    /// Returns nil when the content is internally inconsistent.
    var isConsistent: Bool {
        guard version == Self.currentVersion,
              miners.count <= WatchFleetLimits.maximumMiners,
              Set(miners.map(\.id)).count == miners.count,
              Set(miners.map(\.address)).count == miners.count
        else { return false }
        let ids = Set(miners.map(\.id))
        let readingIDs = readings.map(\.minerID)
        return Set(readingIDs).count == readingIDs.count && readingIDs.allSatisfy(ids.contains)
    }
}

/// Atomic JSON file storage. A nil URL disables persistence.
struct WatchFleetPersistence: Sendable {
    enum LoadResult {
        case empty
        case loaded(WatchFleetSnapshot)
        /// The file could not be trusted and was moved to a unique sibling backup (kept for recovery).
        case corrupt(backup: URL)
        /// The file could not be trusted and could not be moved aside. It must not be overwritten.
        case corruptUnpreserved
    }

    /// Saved files larger than this are not trusted. Real content is a few kilobytes.
    static let maximumFileBytes = 1_048_576

    let url: URL?

    static func defaultURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return base.appendingPathComponent("HashFleetWatch", isDirectory: true)
            .appendingPathComponent("fleet.json", isDirectory: false)
    }

    func load() -> LoadResult {
        guard let url else { return .empty }
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }
        guard let snapshot = readSnapshot(at: url) else { return quarantine(url) }
        return .loaded(snapshot)
    }

    private func readSnapshot(at url: URL) -> WatchFleetSnapshot? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber,
              size.intValue <= Self.maximumFileBytes,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WatchFleetSnapshot.self, from: data),
              snapshot.isConsistent
        else { return nil }
        return snapshot
    }

    func save(_ snapshot: WatchFleetSnapshot) throws {
        guard let url else { return }
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        #if os(watchOS) || os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    /// Moves the unreadable file to a unique sibling. Never deletes or overwrites earlier evidence.
    private func quarantine(_ url: URL) -> LoadResult {
        let stamp = Int(Date().timeIntervalSince1970)
        let name = url.deletingPathExtension().lastPathComponent
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("\(name).corrupt-\(stamp)-\(UUID().uuidString.prefix(8)).json")
        do {
            try FileManager.default.moveItem(at: url, to: backup)
            return .corrupt(backup: backup)
        } catch {
            return .corruptUnpreserved
        }
    }
}
