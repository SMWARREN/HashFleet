import Foundation

/// One share-session lease. Cleanup happens after the native share sheet dismisses, not while a
/// receiving activity may still need the URL. Stale crash leftovers are pruned on the next export.
struct FleetReportTemporaryFile: Identifiable, Sendable {
    enum Format: String, Sendable { case pdf, csv }

    let id: UUID
    let url: URL
    private let directory: URL

    static func create(
        data: Data,
        format: Format,
        capturedAt: Date,
        root: URL = FileManager.default.temporaryDirectory.appendingPathComponent("HashFleetReports", isDirectory: true),
        now: Date = .now
    ) throws -> Self {
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        prune(in: root, before: now.addingTimeInterval(-86_400))
        let id = UUID()
        let directory = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var excluded = directory
            try excluded.setResourceValues(values)
            // Only fixed ASCII components enter the bounded filename, never miner-provided strings.
            let stamp = FleetReportSnapshot.timestamp(capturedAt)
                .filter { $0.isASCII && ($0.isNumber || $0 == "T" || $0 == "Z") }.prefix(20)
            let filename = "hash-fleet-snapshot-\(stamp)-\(id.uuidString.prefix(8)).\(format.rawValue)"
            let url = directory.appendingPathComponent(filename)
            #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            #else
            try data.write(to: url, options: .atomic)
            #endif
            return Self(id: id, url: url, directory: directory)
        } catch {
            try? manager.removeItem(at: directory)
            throw error
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Restricted to UUID-named directories under this feature's private temporary root.
    static func prune(in root: URL, before cutoff: Date) {
        let manager = FileManager.default
        guard let children = try? manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
        ) else { return }
        for child in children {
            guard UUID(uuidString: child.lastPathComponent) != nil,
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]),
                values.isDirectory == true, values.isSymbolicLink != true,
                let modified = values.contentModificationDate, modified < cutoff
            else { continue }
            try? manager.removeItem(at: child)
        }
    }
}
