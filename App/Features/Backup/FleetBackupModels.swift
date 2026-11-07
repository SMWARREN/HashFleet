import Foundation
import HashFleetCore

/// The only data intentionally included in a fleet backup. Credentials, wallet values, raw
/// snapshots, authentication material, and firmware settings are never part of this type.
public struct FleetBackupEntry: Codable, Equatable, Hashable, Sendable {
    public let address: String
    public let name: String

    public init(address: String, name: String) throws {
        self.address = try Self.canonicalAddress(address)
        self.name = try Self.validatedName(name)
    }

    fileprivate init(canonicalAddress: String, validatedName: String) {
        address = canonicalAddress
        name = validatedName
    }

    public static let maxAddressLength = 512
    public static let maxNameLength = 64

    public static func canonicalAddress(_ address: String) throws -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count <= maxAddressLength else {
            throw FleetBackupError.invalidAddress
        }
        let device = MinerDevice(name: "", address: trimmed)
        guard let url = try? device.validatedURL() else {
            throw FleetBackupError.invalidAddress
        }
        let canonical = url.absoluteString
        guard !canonical.isEmpty, canonical.utf8.count <= maxAddressLength else {
            throw FleetBackupError.invalidAddress
        }
        return canonical
    }

    public static func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= maxNameLength,
            !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else {
            throw FleetBackupError.invalidName
        }
        return trimmed
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case address
        case name
    }

    public init(from decoder: Decoder) throws {
        let rawContainer = try decoder.container(keyedBy: FleetBackupCoding.AnyKey.self)
        try FleetBackupCoding.rejectUnknownKeys(rawContainer.allKeys, allowed: ["address", "name"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try FleetBackupCoding.rejectUnknownKeys(container.allKeys, allowed: CodingKeys.allCases)
        let address = try container.decode(String.self, forKey: .address)
        let name = try container.decode(String.self, forKey: .name)
        self.address = try Self.canonicalAddress(address)
        self.name = try Self.validatedName(name)
    }
}

public enum FleetBackupError: Error, Equatable, LocalizedError, Sendable {
    case fileTooLarge
    case malformedJSON
    case unsupportedVersion(Int)
    case tooManyEntries(Int)
    case invalidAddress
    case invalidName
    case invalidEntry(index: Int, reason: String)
    case invalidExistingEntry(index: Int, reason: String)
    case duplicatePreview
    case demoExportDisabled
    case storageUnavailable
    case stalePreview
    case persistenceFailed

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            return "This backup file is too large."
        case .malformedJSON:
            return "This is not a valid Hash Fleet backup file."
        case .unsupportedVersion(let version):
            return "This backup uses version \(version), which this app can't open."
        case .tooManyEntries(let count):
            return "This backup contains too many miners (\(count))."
        case .invalidAddress:
            return "A backup entry contains an unsupported or malformed miner address."
        case .invalidName:
            return "A backup entry contains an invalid miner name."
        case .invalidEntry(let index, let reason):
            return "Backup entry \(index + 1) is invalid: \(reason)."
        case .invalidExistingEntry(let index, let reason):
            return "Saved miner \(index + 1) is invalid: \(reason)."
        case .duplicatePreview:
            return "This restore preview is no longer current. Review it again before applying."
        case .demoExportDisabled:
            return "Demo mode cannot export a backup."
        case .storageUnavailable:
            return "Saved fleet storage needs attention before a restore can be applied."
        case .stalePreview:
            return "The fleet changed after this preview. Review the backup again before applying."
        case .persistenceFailed:
            return "The backup could not be saved, so no changes were applied."
        }
    }
}

public struct FleetBackupDocument: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let maxEntries = 128
    public static let maxFileSize = 256 * 1024

    public let version: Int
    public let entries: [FleetBackupEntry]

    public init(devices: [MinerDevice]) throws {
        guard devices.count <= Self.maxEntries else {
            throw FleetBackupError.tooManyEntries(devices.count)
        }
        var seen = Set<String>()
        var entries: [FleetBackupEntry] = []
        entries.reserveCapacity(devices.count)
        for (index, device) in devices.enumerated() {
            do {
                let entry = try FleetBackupEntry(address: device.address, name: device.name)
                if seen.insert(entry.address).inserted {
                    entries.append(entry)
                }
            } catch let error as FleetBackupError {
                throw FleetBackupError.invalidEntry(index: index, reason: error.localizedDescription)
            } catch {
                throw FleetBackupError.invalidEntry(index: index, reason: error.localizedDescription)
            }
        }
        version = Self.currentVersion
        self.entries = entries
    }

    public init(entries: [FleetBackupEntry]) throws {
        guard entries.count <= Self.maxEntries else {
            throw FleetBackupError.tooManyEntries(entries.count)
        }
        var seen = Set<String>()
        self.entries = entries.filter { seen.insert($0.address).inserted }
        version = Self.currentVersion
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version
        case entries
    }

    public init(from decoder: Decoder) throws {
        let rawContainer = try decoder.container(keyedBy: FleetBackupCoding.AnyKey.self)
        try FleetBackupCoding.rejectUnknownKeys(rawContainer.allKeys, allowed: ["version", "entries"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try FleetBackupCoding.rejectUnknownKeys(container.allKeys, allowed: CodingKeys.allCases)
        let version = try container.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else { throw FleetBackupError.unsupportedVersion(version) }
        var entriesContainer = try container.nestedUnkeyedContainer(forKey: .entries)
        if let count = entriesContainer.count, count > Self.maxEntries {
            throw FleetBackupError.tooManyEntries(count)
        }
        var entries: [FleetBackupEntry] = []
        var seen = Set<String>()
        while !entriesContainer.isAtEnd {
            let index = entries.count
            do {
                let entry = try entriesContainer.decode(FleetBackupEntry.self)
                if seen.insert(entry.address).inserted {
                    entries.append(entry)
                }
            } catch let error as FleetBackupError {
                throw FleetBackupError.invalidEntry(index: index, reason: error.localizedDescription)
            } catch {
                throw FleetBackupError.invalidEntry(index: index, reason: error.localizedDescription)
            }
        }
        self.version = version
        self.entries = entries
    }
}

public struct FleetBackupRestorePreview: Equatable, Sendable {
    public let additions: [FleetBackupEntry]
    public let alreadyPresent: [FleetBackupEntry]
    private let sourceFingerprint: [FleetBackupEntry]

    public var isEmpty: Bool { additions.isEmpty }
    public var additionCount: Int { additions.count }

    public init(
        additions: [FleetBackupEntry],
        alreadyPresent: [FleetBackupEntry],
        sourceFingerprint: [FleetBackupEntry] = []
    ) {
        self.additions = additions
        self.alreadyPresent = alreadyPresent
        self.sourceFingerprint = sourceFingerprint
    }
}

enum FleetBackupCoding {
    struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    static func rejectUnknownKeys(_ keys: [AnyKey], allowed: Set<String>) throws {
        guard keys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw FleetBackupError.malformedJSON
        }
    }

    static func rejectUnknownKeys<K: CodingKey>(_ keys: [K], allowed: [K]) throws {
        let allowedValues = Set(allowed.map(\.stringValue))
        guard keys.allSatisfy({ allowedValues.contains($0.stringValue) }) else {
            throw FleetBackupError.malformedJSON
        }
    }
}
