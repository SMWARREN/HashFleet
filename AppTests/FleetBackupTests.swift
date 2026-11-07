import Foundation
import Testing
import HashFleetCore
@testable import HashFleet

@Suite("Fleet backup", .serialized)
@MainActor
struct FleetBackupTests {
    @Test func exportIsVersionedBoundedAndContainsOnlyAddressAndName() throws {
        let devices = [
            MinerDevice(name: "Desk", address: "HTTP://Desk.local:80/"),
            MinerDevice(name: "Duplicate", address: "http://desk.local"),
            MinerDevice(name: "Garage", address: "garage.local")
        ]
        let data = try FleetBackup.encode(devices: devices)
        #expect(data.count <= FleetBackupDocument.maxFileSize)
        let json = String(bytes: data, encoding: .utf8) ?? ""
        #expect(json.contains("\"version\""))
        #expect(json.contains("\"entries\""))
        #expect(!json.contains("password"))
        #expect(!json.contains("wallet"))
        #expect(!json.contains("snapshot"))
        #expect(!json.contains("seed"))

        let document = try FleetBackup.decode(data)
        #expect(document.version == FleetBackupDocument.currentVersion)
        #expect(document.entries.count == 2)
        #expect(document.entries[0].address == "http://desk.local")
        #expect(document.entries[0].name == "Desk")
    }

    @Test func unsupportedSchemesMalformedEntriesAndUnexpectedKeysAreRejected() throws {
        #expect(throws: FleetBackupError.invalidEntry(index: 0, reason: FleetBackupError.invalidAddress.localizedDescription)) {
            _ = try FleetBackup.decode(Data(#"{"version":1,"entries":[{"address":"ftp://miner.local","name":"Miner"}]}"#.utf8))
        }
        #expect(throws: FleetBackupError.malformedJSON) {
            _ = try FleetBackup.decode(Data(#"{"version":1,"entries":[],"unexpected":true}"#.utf8))
        }
        #expect(throws: FleetBackupError.unsupportedVersion(2)) {
            _ = try FleetBackup.decode(Data(#"{"version":2,"entries":[]}"#.utf8))
        }
        #expect(throws: FleetBackupError.fileTooLarge) {
            _ = try FleetBackup.decode(Data(repeating: 0x20, count: FleetBackupDocument.maxFileSize + 1))
        }
        #expect(throws: FleetBackupError.invalidName) {
            _ = try FleetBackupEntry(address: "miner.local", name: "bad\nname")
        }
        #expect(throws: FleetBackupError.tooManyEntries(129)) {
            let entries = try (0..<129).map { index in
                try FleetBackupEntry(address: "miner\(index).local", name: "Miner \(index)")
            }
            _ = try FleetBackupDocument(entries: entries)
        }
    }

    @Test func previewSuppressesCanonicalDuplicatesAndNeverOverwrites() throws {
        let current = [MinerDevice(name: "Original", address: "http://desk.local")]
        let document = try FleetBackupDocument(entries: [
            try FleetBackupEntry(address: "DESK.local:80", name: "Changed name"),
            try FleetBackupEntry(address: "new.local", name: "New miner"),
            try FleetBackupEntry(address: "http://new.local/", name: "Duplicate new")
        ])
        let preview = try FleetBackup.preview(document: document, currentDevices: current)
        #expect(preview.additions.map(\.name) == ["New miner"])
        #expect(preview.alreadyPresent.map(\.name) == ["Changed name"])
    }

    @Test func invalidOrCancelledPreviewDoesNotMutateStore() throws {
        let fixture = try fixture(devices: [MinerDevice(name: "Saved", address: "saved.local")])
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let store = fixture.store
        let before = store.devices

        #expect(throws: (any Error).self) {
            _ = try store.fleetBackupPreview(data: Data(#"{"version":1,"entries":[{"address":"ftp://bad","name":"Bad"}]}"#.utf8))
        }
        #expect(store.devices == before)

        let newData = try FleetBackup.encode(devices: [MinerDevice(name: "New", address: "new.local")])
        let preview = try store.fleetBackupPreview(data: newData)
        #expect(preview.additionCount == 1)
        // The caller can cancel after this preview. No apply call means no mutation.
        #expect(store.devices == before)
    }

    @Test func emptyAndAllDuplicateRestoreDoNotExitDemo() throws {
        let fixture = try fixture(devices: [MinerDevice(name: "Saved", address: "saved.local")])
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let store = fixture.store
        store.loadDemo()
        #expect(store.isDemo)
        let saved = store.savedDevices

        let emptyData = try FleetBackup.encode(devices: [])
        let emptyPreview = try store.fleetBackupPreview(data: emptyData)
        #expect(try store.applyFleetBackup(data: emptyData, expectedPreview: emptyPreview) == 0)
        #expect(store.isDemo)
        #expect(store.savedDevices == saved)

        let duplicateData = try FleetBackup.encode(devices: saved)
        let duplicatePreview = try store.fleetBackupPreview(data: duplicateData)
        #expect(duplicatePreview.isEmpty)
        #expect(try store.applyFleetBackup(data: duplicateData, expectedPreview: duplicatePreview) == 0)
        #expect(store.isDemo)
        #expect(store.savedDevices == saved)
    }

    @Test func confirmedRestorePreservesExistingIdentityAndNamesAndReloads() throws {
        let fixture = try fixture(devices: [MinerDevice(name: "Original", address: "saved.local")])
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let store = fixture.store
        let original = try #require(store.devices.first)
        let data = try FleetBackup.encode(devices: [MinerDevice(name: "Imported", address: "new.local")])
        let preview = try store.fleetBackupPreview(data: data)

        #expect(try store.applyFleetBackup(data: data, expectedPreview: preview) == 1)
        #expect(store.devices.count == 2)
        #expect(store.devices.first?.id == original.id)
        #expect(store.devices.first?.name == "Original")
        #expect(store.devices.last?.name == "Imported")
        #expect(store.devices.last?.address == "http://new.local")

        let restored = FleetStore(defaults: fixture.defaults)
        #expect(restored.devices.count == 2)
        #expect(restored.devices.first?.id == original.id)
        #expect(restored.devices.first?.name == "Original")
        #expect(restored.devices.last?.name == "Imported")
    }

    @Test func confirmedNonEmptyDemoRestoreExitsDemoOnlyAfterApply() throws {
        let fixture = try fixture(devices: [MinerDevice(name: "Saved", address: "saved.local")])
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let store = fixture.store
        store.loadDemo()
        let saved = try #require(store.savedDevices.first)
        let data = try FleetBackup.encode(devices: [MinerDevice(name: "Imported", address: "new.local")])
        let preview = try store.fleetBackupPreview(data: data)
        #expect(store.isDemo)
        #expect(preview.additionCount == 1)

        #expect(try store.applyFleetBackup(data: data, expectedPreview: preview) == 1)
        #expect(!store.isDemo)
        #expect(store.savedDevices.isEmpty)
        #expect(store.devices.first?.id == saved.id)
        #expect(store.devices.first?.name == "Saved")
        #expect(store.devices.last?.name == "Imported")
    }

    @Test func boundedFileReaderNeverLoadsPastBackupLimit() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hashfleet-backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let oversized = root.appendingPathComponent("oversized.json")
        try Data(repeating: 0x20, count: FleetBackupDocument.maxFileSize + 1).write(to: oversized)
        #expect(throws: FleetBackupError.fileTooLarge) {
            _ = try FleetBackup.readBoundedFile(from: oversized)
        }

        let valid = root.appendingPathComponent("valid.json")
        let validData = try FleetBackup.encode(devices: [MinerDevice(name: "Desk", address: "desk.local")])
        try validData.write(to: valid)
        #expect(try FleetBackup.readBoundedFile(from: valid) == validData)

        #expect(throws: FleetBackupError.malformedJSON) {
            _ = try FleetBackup.readBoundedFile(from: root)
        }
    }

    @Test func confirmationRevalidationRejectsStalePreviewWithoutMutation() throws {
        let fixture = try fixture(devices: [MinerDevice(name: "Original", address: "saved.local")])
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let store = fixture.store
        let data = try FleetBackup.encode(devices: [MinerDevice(name: "Imported", address: "new.local")])
        let preview = try store.fleetBackupPreview(data: data)
        try store.add(name: "Another", address: "another.local")
        let before = store.devices

        #expect(throws: FleetBackupError.stalePreview) {
            _ = try store.applyFleetBackup(data: data, expectedPreview: preview)
        }
        #expect(store.devices == before)
    }

    @Test func fleetBackupErrorDescriptionsAreNonEmpty() {
        let errors: [FleetBackupError] = [
            .fileTooLarge,
            .malformedJSON,
            .unsupportedVersion(99),
            .tooManyEntries(200),
            .invalidAddress,
            .invalidName,
            .invalidEntry(index: 0, reason: "bad"),
            .invalidExistingEntry(index: 1, reason: "bad existing"),
            .duplicatePreview,
            .demoExportDisabled,
            .storageUnavailable,
            .stalePreview,
            .persistenceFailed
        ]
        for err in errors {
            #expect(err.errorDescription != nil)
            #expect(!err.errorDescription!.isEmpty)
        }
    }

    @Test func fleetBackupEntryValidationLimitsAndControlCharacters() {
        let longAddress = String(repeating: "a", count: FleetBackupEntry.maxAddressLength + 1)
        #expect(throws: FleetBackupError.invalidAddress) {
            try FleetBackupEntry.canonicalAddress(longAddress)
        }

        let longName = String(repeating: "n", count: FleetBackupEntry.maxNameLength + 1)
        #expect(throws: FleetBackupError.invalidName) {
            try FleetBackupEntry.validatedName(longName)
        }

        let controlName = "Name\u{0007}"
        #expect(throws: FleetBackupError.invalidName) {
            try FleetBackupEntry.validatedName(controlName)
        }
    }

    @Test func fleetBackupDocumentInitFromDevicesHandlesInvalidAddress() {
        let invalidDevice = MinerDevice(name: "Test", address: "ftp://invalid")
        #expect(throws: FleetBackupError.self) {
            try FleetBackupDocument(devices: [invalidDevice])
        }
    }

    private struct Fixture {
        let store: FleetStore
        let defaults: UserDefaults
        let suite: String
    }

    private func fixture(devices: [MinerDevice]) throws -> Fixture {
        let suite = "app.hashfleet.backup.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(try JSONEncoder().encode(devices), forKey: FleetStore.storageKey)
        return Fixture(store: FleetStore(defaults: defaults), defaults: defaults, suite: suite)
    }
}
