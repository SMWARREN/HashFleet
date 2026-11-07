import Foundation
import HashFleetCore

public enum FleetBackup {
    /// Backups contain private local miner addresses and names. They intentionally exclude passwords,
    /// wallets, raw snapshots, authentication material, and seeds.
    public static let privacyWarning =
        "Backups include private local miner addresses and names. They never include passwords, wallets, " +
        "raw snapshots, authentication, or seeds. Share or import a file only when you choose to."

    public static func encode(devices: [MinerDevice]) throws -> Data {
        let document = try FleetBackupDocument(devices: devices)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        guard data.count <= FleetBackupDocument.maxFileSize else {
            throw FleetBackupError.fileTooLarge
        }
        return data
    }

    static func readBoundedFile(from url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile != false else { throw FleetBackupError.malformedJSON }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: FleetBackupDocument.maxFileSize + 1) ?? Data()
        guard data.count <= FleetBackupDocument.maxFileSize else {
            throw FleetBackupError.fileTooLarge
        }
        return data
    }

    public static func decode(_ data: Data) throws -> FleetBackupDocument {
        guard data.count <= FleetBackupDocument.maxFileSize else {
            throw FleetBackupError.fileTooLarge
        }
        guard let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any]
        else {
            throw FleetBackupError.malformedJSON
        }
        guard Set(dictionary.keys) == ["version", "entries"],
            let rawEntries = dictionary["entries"] as? [Any],
            rawEntries.count <= FleetBackupDocument.maxEntries,
            rawEntries.allSatisfy({
                guard let entry = $0 as? [String: Any] else { return false }
                return Set(entry.keys) == ["address", "name"]
            })
        else {
            throw FleetBackupError.malformedJSON
        }
        do {
            return try JSONDecoder().decode(FleetBackupDocument.self, from: data)
        } catch let error as FleetBackupError {
            throw error
        } catch {
            throw FleetBackupError.malformedJSON
        }
    }

    public static func preview(
        document: FleetBackupDocument,
        currentDevices: [MinerDevice]
    ) throws -> FleetBackupRestorePreview {
        guard document.version == FleetBackupDocument.currentVersion else {
            throw FleetBackupError.unsupportedVersion(document.version)
        }
        guard currentDevices.count <= FleetBackupDocument.maxEntries else {
            throw FleetBackupError.tooManyEntries(currentDevices.count)
        }

        var existingAddresses = Set<String>()
        var sourceFingerprint: [FleetBackupEntry] = []
        for (index, device) in currentDevices.enumerated() {
            do {
                let current = try FleetBackupEntry(address: device.address, name: device.name)
                existingAddresses.insert(current.address)
                sourceFingerprint.append(current)
            } catch let error as FleetBackupError {
                throw FleetBackupError.invalidExistingEntry(index: index, reason: error.localizedDescription)
            } catch {
                throw FleetBackupError.invalidExistingEntry(index: index, reason: error.localizedDescription)
            }
        }

        var additions: [FleetBackupEntry] = []
        var alreadyPresent: [FleetBackupEntry] = []
        for entry in document.entries {
            if existingAddresses.contains(entry.address) {
                alreadyPresent.append(entry)
            } else {
                additions.append(entry)
                // This makes the no-overwrite/additions-only rule explicit even if a future document
                // decoder changes its duplicate handling.
                existingAddresses.insert(entry.address)
            }
        }
        return FleetBackupRestorePreview(
            additions: additions,
            alreadyPresent: alreadyPresent,
            sourceFingerprint: sourceFingerprint
        )
    }
}
